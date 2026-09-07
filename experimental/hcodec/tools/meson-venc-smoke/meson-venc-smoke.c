// SPDX-License-Identifier: GPL-2.0-only
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <linux/dma-buf.h>
#include <linux/dma-heap.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

struct mapped_buffer {
	void *address;
	size_t length;
	int dmabuf_fd;
};

enum input_pattern {
	PATTERN_FLAT,
	PATTERN_GRADIENT,
	PATTERN_CHECKER,
	PATTERN_NOISE,
	PATTERN_MOTION,
};

enum rate_control_mode {
	RATE_CONTROL_CQ,
	RATE_CONTROL_VBR,
	RATE_CONTROL_CBR,
};

static void usage(FILE *stream, const char *program)
{
	fprintf(stream,
		"Usage: %s DEVICE OUTPUT.h264 "
		"[WIDTH HEIGHT [FRAMES [GOP [FORCE_FRAME [PATTERN [QP "
		"[MEMORY [INPUT_FORMAT [RC_MODE [BITRATE [PEAK_BITRATE "
		"[FPS [SWITCH_FRAME [SWITCH_BITRATE]]]]]]]]]]]]]]\n"
		"PATTERN: flat (default), gradient, checker, noise, motion; "
		"QP: 0..51 (default 26); MEMORY: mmap (default), dmabuf; "
		"INPUT_FORMAT: nv12 (default), yuyv; RC_MODE: cq (default), "
		"vbr, cbr; bitrates are in bit/s; FPS: 1..120 (default 30)\n",
		program);
}

static const char *rate_control_name(enum rate_control_mode mode)
{
	switch (mode) {
	case RATE_CONTROL_CQ:
		return "CQ";
	case RATE_CONTROL_VBR:
		return "VBR";
	case RATE_CONTROL_CBR:
		return "CBR";
	}
	return "unknown";
}

static int parse_rate_control(const char *name, enum rate_control_mode *mode)
{
	if (!strcmp(name, "cq"))
		*mode = RATE_CONTROL_CQ;
	else if (!strcmp(name, "vbr"))
		*mode = RATE_CONTROL_VBR;
	else if (!strcmp(name, "cbr"))
		*mode = RATE_CONTROL_CBR;
	else
		return -1;
	return 0;
}

static const char *pattern_name(enum input_pattern pattern)
{
	switch (pattern) {
	case PATTERN_FLAT:
		return "flat";
	case PATTERN_GRADIENT:
		return "gradient";
	case PATTERN_CHECKER:
		return "checker";
	case PATTERN_NOISE:
		return "noise";
	case PATTERN_MOTION:
		return "motion";
	}
	return "unknown";
}

static int parse_pattern(const char *name, enum input_pattern *pattern)
{
	static const char *const names[] = {
		[PATTERN_FLAT] = "flat",
		[PATTERN_GRADIENT] = "gradient",
		[PATTERN_CHECKER] = "checker",
		[PATTERN_NOISE] = "noise",
		[PATTERN_MOTION] = "motion",
	};
	size_t i;

	for (i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
		if (!strcmp(name, names[i])) {
			*pattern = i;
			return 0;
		}
	}
	return -1;
}

static uint32_t xorshift32(uint32_t *state)
{
	uint32_t value = *state;

	value ^= value << 13;
	value ^= value >> 17;
	value ^= value << 5;
	*state = value;
	return value;
}

static void fill_nv12(void *address, uint32_t width, uint32_t height,
		      uint32_t bytesperline, uint32_t frame,
		      enum input_pattern pattern)
{
	uint8_t *y_plane = address;
	uint8_t *uv_plane = y_plane + (size_t)bytesperline * height;
	uint32_t state = 0x6d2b79f5U ^ (frame * 0x9e3779b9U);
	uint32_t square_size = width < height ? width / 5 : height / 5;
	uint32_t square_x;
	uint32_t square_y;
	uint32_t x;
	uint32_t y;

	if (square_size < 16)
		square_size = 16;
	square_x = (uint64_t)frame * 13 % (width + square_size) - square_size;
	square_y = (uint64_t)frame * 7 % (height + square_size) - square_size;

	memset(y_plane, 0x10, (size_t)bytesperline * height);
	memset(uv_plane, 0x80, (size_t)bytesperline * (height / 2));
	for (y = 0; y < height; y++) {
		for (x = 0; x < width; x++) {
			switch (pattern) {
			case PATTERN_FLAT:
				y_plane[(size_t)y * bytesperline + x] = 0x40;
				break;
			case PATTERN_GRADIENT:
				y_plane[(size_t)y * bytesperline + x] =
					16 + ((x * 151 / width + y * 68 / height) % 220);
				break;
			case PATTERN_CHECKER:
				y_plane[(size_t)y * bytesperline + x] =
					(((x / 16) ^ (y / 16)) & 1) ? 220 : 24;
				break;
			case PATTERN_NOISE:
				y_plane[(size_t)y * bytesperline + x] =
					16 + xorshift32(&state) % 220;
				break;
			case PATTERN_MOTION:
				y_plane[(size_t)y * bytesperline + x] =
					16 + ((x * 73 / width + y * 47 / height) % 160);
				if (x - square_x < square_size &&
				    y - square_y < square_size)
					y_plane[(size_t)y * bytesperline + x] =
						(((x / 8) ^ (y / 8)) & 1) ? 235 : 32;
				break;
			}
		}
	}

	for (y = 0; y < height / 2; y++) {
		for (x = 0; x + 1 < width; x += 2) {
			uint8_t u = 128;
			uint8_t v = 128;

			if (pattern == PATTERN_GRADIENT ||
			    pattern == PATTERN_CHECKER) {
				u = 32 + x * 192 / width;
				v = 224 - y * 192 / (height / 2);
			} else if (pattern == PATTERN_NOISE) {
				u = 16 + xorshift32(&state) % 225;
				v = 16 + xorshift32(&state) % 225;
			} else if (pattern == PATTERN_MOTION &&
				   x - square_x < square_size &&
				   y * 2 - square_y < square_size) {
				u = 48;
				v = 208;
			}
			uv_plane[(size_t)y * bytesperline + x] = u;
			uv_plane[(size_t)y * bytesperline + x + 1] = v;
		}
	}
}

static uint8_t pattern_luma(enum input_pattern pattern, uint32_t width,
			    uint32_t height, uint32_t frame, uint32_t x,
			    uint32_t y, uint32_t square_x, uint32_t square_y,
			    uint32_t square_size, uint32_t *state)
{
	switch (pattern) {
	case PATTERN_FLAT:
		return 0x40;
	case PATTERN_GRADIENT:
		return 16 + ((x * 151 / width + y * 68 / height) % 220);
	case PATTERN_CHECKER:
		return (((x / 16) ^ (y / 16)) & 1) ? 220 : 24;
	case PATTERN_NOISE:
		return 16 + xorshift32(state) % 220;
	case PATTERN_MOTION:
		if (x - square_x < square_size && y - square_y < square_size)
			return (((x / 8) ^ (y / 8)) & 1) ? 235 : 32;
		return 16 + ((x * 73 / width + y * 47 / height) % 160);
	}
	return frame & 0xff;
}

static void fill_yuyv(void *address, uint32_t width, uint32_t height,
		      uint32_t bytesperline, uint32_t frame,
		      enum input_pattern pattern)
{
	uint8_t *data = address;
	uint32_t state = 0x6d2b79f5U ^ (frame * 0x9e3779b9U);
	uint32_t square_size = width < height ? width / 5 : height / 5;
	uint32_t square_x;
	uint32_t square_y;
	uint32_t x;
	uint32_t y;

	if (square_size < 16)
		square_size = 16;
	square_x = (uint64_t)frame * 13 % (width + square_size) - square_size;
	square_y = (uint64_t)frame * 7 % (height + square_size) - square_size;
	memset(data, 0x80, (size_t)bytesperline * height);

	for (y = 0; y < height; y++) {
		for (x = 0; x + 1 < width; x += 2) {
			uint8_t *pair = data + (size_t)y * bytesperline + x * 2;
			uint8_t u = 128;
			uint8_t v = 128;

			pair[0] = pattern_luma(pattern, width, height, frame, x, y,
					       square_x, square_y, square_size,
					       &state);
			pair[2] = pattern_luma(pattern, width, height, frame, x + 1,
					       y, square_x, square_y, square_size,
					       &state);
			if (pattern == PATTERN_GRADIENT ||
			    pattern == PATTERN_CHECKER) {
				u = 32 + x * 192 / width;
				v = 224 - y * 192 / height;
			} else if (pattern == PATTERN_NOISE) {
				u = 16 + xorshift32(&state) % 225;
				v = 16 + xorshift32(&state) % 225;
			} else if (pattern == PATTERN_MOTION &&
				   x - square_x < square_size &&
				   y - square_y < square_size) {
				u = 48;
				v = 208;
			}
			pair[1] = u;
			pair[3] = v;
		}
	}
}

static void fill_input(void *address, uint32_t fourcc, uint32_t width,
		       uint32_t height, uint32_t bytesperline, uint32_t frame,
		       enum input_pattern pattern)
{
	if (fourcc == V4L2_PIX_FMT_YUYV)
		fill_yuyv(address, width, height, bytesperline, frame, pattern);
	else
		fill_nv12(address, width, height, bytesperline, frame, pattern);
}

static int xioctl(int fd, unsigned long request, void *argument)
{
	int ret;

	do {
		ret = ioctl(fd, request, argument);
	} while (ret < 0 && errno == EINTR);
	return ret;
}

static int set_format(int fd, enum v4l2_buf_type type, uint32_t fourcc,
		      uint32_t width, uint32_t height,
		      struct v4l2_pix_format_mplane *result)
{
	struct v4l2_format format = { 0 };

	format.type = type;
	format.fmt.pix_mp.width = width;
	format.fmt.pix_mp.height = height;
	format.fmt.pix_mp.pixelformat = fourcc;
	format.fmt.pix_mp.field = V4L2_FIELD_NONE;
	format.fmt.pix_mp.num_planes = 1;
	if (xioctl(fd, VIDIOC_S_FMT, &format) < 0)
		return -1;
	*result = format.fmt.pix_mp;
	return 0;
}

static int map_buffer(int fd, enum v4l2_buf_type type,
		      struct mapped_buffer *mapped)
{
	struct v4l2_requestbuffers request = { 0 };
	struct v4l2_plane plane = { 0 };
	struct v4l2_buffer buffer = { 0 };

	request.count = 1;
	request.type = type;
	request.memory = V4L2_MEMORY_MMAP;
	if (xioctl(fd, VIDIOC_REQBUFS, &request) < 0 || request.count < 1)
		return -1;

	buffer.type = type;
	buffer.memory = V4L2_MEMORY_MMAP;
	buffer.index = 0;
	buffer.length = 1;
	buffer.m.planes = &plane;
	if (xioctl(fd, VIDIOC_QUERYBUF, &buffer) < 0)
		return -1;

	mapped->length = plane.length;
	mapped->dmabuf_fd = -1;
	mapped->address = mmap(NULL, mapped->length, PROT_READ | PROT_WRITE,
			       MAP_SHARED, fd, plane.m.mem_offset);
	return mapped->address == MAP_FAILED ? -1 : 0;
}

static int open_cma_heap(void)
{
	static const char * const paths[] = {
		"/dev/dma_heap/linux,cma",
		"/dev/dma_heap/reserved",
	};
	size_t i;

	for (i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
		int fd = open(paths[i], O_RDWR | O_CLOEXEC);

		if (fd >= 0)
			return fd;
	}
	return -1;
}

static int map_dmabuf(int fd, enum v4l2_buf_type type, size_t size,
		      struct mapped_buffer *mapped)
{
	struct dma_heap_allocation_data allocation = {
		.len = size,
		.fd_flags = O_RDWR | O_CLOEXEC,
	};
	struct v4l2_requestbuffers request = {
		.count = 1,
		.type = type,
		.memory = V4L2_MEMORY_DMABUF,
	};
	int heap_fd;

	heap_fd = open_cma_heap();
	if (heap_fd < 0)
		return -1;
	if (xioctl(heap_fd, DMA_HEAP_IOCTL_ALLOC, &allocation) < 0) {
		close(heap_fd);
		return -1;
	}
	close(heap_fd);

	mapped->length = size;
	mapped->dmabuf_fd = allocation.fd;
	mapped->address = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED,
			       mapped->dmabuf_fd, 0);
	if (mapped->address == MAP_FAILED)
		return -1;
	if (xioctl(fd, VIDIOC_REQBUFS, &request) < 0 || request.count < 1)
		return -1;
	return 0;
}

static int sync_dmabuf(const struct mapped_buffer *mapped, uint64_t flags)
{
	struct dma_buf_sync sync = { .flags = flags };

	if (mapped->dmabuf_fd < 0)
		return 0;
	return xioctl(mapped->dmabuf_fd, DMA_BUF_IOCTL_SYNC, &sync);
}

static int queue_buffer(int fd, enum v4l2_buf_type type,
			enum v4l2_memory memory,
			const struct mapped_buffer *mapped, size_t bytesused)
{
	struct v4l2_plane plane = { 0 };
	struct v4l2_buffer buffer = { 0 };

	buffer.type = type;
	buffer.memory = memory;
	buffer.index = 0;
	buffer.length = 1;
	buffer.m.planes = &plane;
	plane.bytesused = bytesused;
	if (memory == V4L2_MEMORY_DMABUF) {
		plane.m.fd = mapped->dmabuf_fd;
		plane.length = mapped->length;
	}
	return xioctl(fd, VIDIOC_QBUF, &buffer);
}

static int dequeue_buffer(int fd, enum v4l2_buf_type type,
			  enum v4l2_memory memory, size_t *bytesused,
			  uint32_t *flags)
{
	struct v4l2_plane plane = { 0 };
	struct v4l2_buffer buffer = { 0 };

	buffer.type = type;
	buffer.memory = memory;
	buffer.length = 1;
	buffer.m.planes = &plane;
	if (xioctl(fd, VIDIOC_DQBUF, &buffer) < 0)
		return -1;
	if (buffer.flags & V4L2_BUF_FLAG_ERROR) {
		errno = EIO;
		return -1;
	}
	*bytesused = plane.bytesused;
	if (flags)
		*flags = buffer.flags;
	return 0;
}

static int set_control(int fd, uint32_t id, int32_t value)
{
	struct v4l2_control control = {
		.id = id,
		.value = value,
	};

	return xioctl(fd, VIDIOC_S_CTRL, &control);
}

static int set_frame_rate(int fd, uint32_t fps)
{
	struct v4l2_streamparm parm = { 0 };

	parm.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	parm.parm.output.timeperframe.numerator = 1;
	parm.parm.output.timeperframe.denominator = fps;
	if (xioctl(fd, VIDIOC_S_PARM, &parm) < 0)
		return -1;
	if (!parm.parm.output.timeperframe.numerator ||
	    parm.parm.output.timeperframe.denominator /
	    parm.parm.output.timeperframe.numerator != fps) {
		errno = ERANGE;
		return -1;
	}
	return 0;
}

static int stream(int fd, enum v4l2_buf_type type, bool on)
{
	return xioctl(fd, on ? VIDIOC_STREAMON : VIDIOC_STREAMOFF, &type);
}

static int write_all(int fd, const uint8_t *data, size_t size)
{
	while (size) {
		ssize_t written = write(fd, data, size);

		if (written < 0) {
			if (errno == EINTR)
				continue;
			return -1;
		}
		data += written;
		size -= written;
	}
	return 0;
}

static bool find_nal(const uint8_t *data, size_t size, uint8_t wanted)
{
	size_t i;

	for (i = 0; i + 4 < size; i++) {
		size_t header;

		if (!data[i] && !data[i + 1] && data[i + 2] == 1)
			header = i + 3;
		else if (!data[i] && !data[i + 1] && !data[i + 2] &&
			 data[i + 3] == 1)
			header = i + 4;
		else
			continue;
		if (header < size && (data[header] & 0x1f) == wanted)
			return true;
	}
	return false;
}

static size_t find_filler_size(const uint8_t *data, size_t size)
{
	size_t i;

	for (i = 0; i + 4 < size; i++) {
		size_t header;

		if (!data[i] && !data[i + 1] && data[i + 2] == 1)
			header = i + 3;
		else if (!data[i] && !data[i + 1] && !data[i + 2] &&
			 data[i + 3] == 1)
			header = i + 4;
		else
			continue;
		if (header < size && (data[header] & 0x1f) == 12)
			return size - i;
	}
	return 0;
}

int main(int argc, char **argv)
{
	struct v4l2_capability capability = { 0 };
	struct v4l2_pix_format_mplane output_format;
	struct v4l2_pix_format_mplane capture_format;
	struct mapped_buffer output = { .dmabuf_fd = -1 };
	struct mapped_buffer capture = { .dmabuf_fd = -1 };
	struct pollfd poll_fd;
	enum v4l2_buf_type output_type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	enum v4l2_buf_type capture_type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	uint32_t width = 640;
	uint32_t height = 480;
	uint32_t frames = 1;
	uint32_t gop = 30;
	uint32_t force_frame = UINT32_MAX;
	uint32_t qp = 26;
	uint32_t bitrate = 4000000;
	uint32_t peak_bitrate = 8000000;
	uint32_t fps = 30;
	uint32_t switch_frame = UINT32_MAX;
	uint32_t switch_bitrate = 0;
	uint32_t frame_index = 0;
	uint32_t capture_flags = 0;
	uint32_t idr_frames = 0;
	uint32_t p_frames = 0;
	enum input_pattern pattern = PATTERN_FLAT;
	enum v4l2_memory memory = V4L2_MEMORY_MMAP;
	uint32_t input_fourcc = V4L2_PIX_FMT_NV12;
	size_t output_size;
	size_t capture_size = 0;
	size_t total_size = 0;
	size_t filler_size = 0;
	size_t switch_size = 0;
	size_t ignored;
	struct timespec started;
	struct timespec finished;
	double elapsed;
	double reported_target;
	bool output_done = false;
	bool capture_done = false;
	enum rate_control_mode rc_mode = RATE_CONTROL_CQ;
	int output_fd = -1;
	int fd = -1;
	int ret = 1;

	if (argc == 2 && !strcmp(argv[1], "--help")) {
		usage(stdout, argv[0]);
		return 0;
	}
	if (argc != 3 && (argc < 5 || argc > 18)) {
		usage(stderr, argv[0]);
		return 2;
	}
	if (argc >= 5) {
		width = strtoul(argv[3], NULL, 0);
		height = strtoul(argv[4], NULL, 0);
	}
	if (argc >= 6)
		frames = strtoul(argv[5], NULL, 0);
	if (argc >= 7)
		gop = strtoul(argv[6], NULL, 0);
	if (argc >= 8)
		force_frame = strtoul(argv[7], NULL, 0);
	if (argc >= 9 && parse_pattern(argv[8], &pattern) < 0) {
		fprintf(stderr, "unknown input pattern: %s\n", argv[8]);
		usage(stderr, argv[0]);
		return 2;
	}
	if (argc >= 10) {
		qp = strtoul(argv[9], NULL, 0);
		if (qp > 51) {
			fprintf(stderr, "QP must be between 0 and 51\n");
			return 2;
		}
	}
	if (argc >= 11) {
		if (!strcmp(argv[10], "dmabuf"))
			memory = V4L2_MEMORY_DMABUF;
		else if (strcmp(argv[10], "mmap")) {
			fprintf(stderr, "MEMORY must be mmap or dmabuf\n");
			return 2;
		}
	}
	if (argc >= 12) {
		if (!strcmp(argv[11], "yuyv"))
			input_fourcc = V4L2_PIX_FMT_YUYV;
		else if (strcmp(argv[11], "nv12")) {
			fprintf(stderr, "INPUT_FORMAT must be nv12 or yuyv\n");
			return 2;
		}
	}
	if (argc >= 13 && parse_rate_control(argv[12], &rc_mode) < 0) {
		fprintf(stderr, "RC_MODE must be cq, vbr or cbr\n");
		return 2;
	}
	if (argc >= 14)
		bitrate = strtoul(argv[13], NULL, 0);
	if (argc >= 15)
		peak_bitrate = strtoul(argv[14], NULL, 0);
	if (argc >= 16)
		fps = strtoul(argv[15], NULL, 0);
	if (argc >= 17)
		switch_frame = strtoul(argv[16], NULL, 0);
	if (argc >= 18)
		switch_bitrate = strtoul(argv[17], NULL, 0);
	if (!bitrate || !peak_bitrate) {
		fprintf(stderr, "bitrates must be greater than zero\n");
		return 2;
	}
	if (!fps || fps > 120) {
		fprintf(stderr, "FPS must be between 1 and 120\n");
		return 2;
	}
	if (switch_frame != UINT32_MAX &&
	    (!switch_frame || switch_frame >= frames || !switch_bitrate)) {
		fprintf(stderr, "bitrate switch requires FRAME in 1..FRAMES-1 "
				"and a nonzero new bitrate\n");
		return 2;
	}
	if (!frames) {
		fprintf(stderr, "frame count must be greater than zero\n");
		return 2;
	}
	if (!gop) {
		fprintf(stderr, "GOP must be greater than zero\n");
		return 2;
	}

	fd = open(argv[1], O_RDWR | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) {
		perror("open video device");
		goto out;
	}
	if (xioctl(fd, VIDIOC_QUERYCAP, &capability) < 0) {
		perror("VIDIOC_QUERYCAP");
		goto out;
	}
	if (!(capability.device_caps & V4L2_CAP_VIDEO_M2M_MPLANE) ||
	    !(capability.device_caps & V4L2_CAP_STREAMING)) {
		fprintf(stderr, "%s is not a streaming multiplanar M2M device\n",
			argv[1]);
		goto out;
	}
	if (set_control(fd, V4L2_CID_MPEG_VIDEO_GOP_SIZE, gop) < 0) {
		perror("set GOP size");
		goto out;
	}
	if (set_control(fd, V4L2_CID_MPEG_VIDEO_H264_I_FRAME_QP, qp) < 0 ||
	    set_control(fd, V4L2_CID_MPEG_VIDEO_H264_P_FRAME_QP, qp) < 0) {
		perror("set H.264 QP");
		goto out;
	}
	if (argc >= 13) {
		int32_t v4l2_mode = V4L2_MPEG_VIDEO_BITRATE_MODE_CQ;

		if (rc_mode == RATE_CONTROL_VBR)
			v4l2_mode = V4L2_MPEG_VIDEO_BITRATE_MODE_VBR;
		else if (rc_mode == RATE_CONTROL_CBR)
			v4l2_mode = V4L2_MPEG_VIDEO_BITRATE_MODE_CBR;
		if (set_frame_rate(fd, fps) < 0 ||
		    set_control(fd, V4L2_CID_MPEG_VIDEO_BITRATE,
				bitrate) < 0 ||
		    set_control(fd, V4L2_CID_MPEG_VIDEO_BITRATE_PEAK,
				peak_bitrate) < 0 ||
		    set_control(fd, V4L2_CID_MPEG_VIDEO_FRAME_RC_ENABLE, 1) < 0 ||
		    set_control(fd, V4L2_CID_MPEG_VIDEO_BITRATE_MODE,
				v4l2_mode) < 0) {
			perror("configure rate control");
			goto out;
		}
	}

	if (set_format(fd, output_type, input_fourcc, width, height,
		       &output_format) < 0 ||
	    set_format(fd, capture_type, V4L2_PIX_FMT_H264, width, height,
		       &capture_format) < 0) {
		perror("VIDIOC_S_FMT");
		goto out;
	}
	if ((memory == V4L2_MEMORY_MMAP &&
	     (map_buffer(fd, output_type, &output) < 0 ||
	      map_buffer(fd, capture_type, &capture) < 0)) ||
	    (memory == V4L2_MEMORY_DMABUF &&
	     (map_dmabuf(fd, output_type,
			 output_format.plane_fmt[0].sizeimage, &output) < 0 ||
	      map_dmabuf(fd, capture_type,
			 capture_format.plane_fmt[0].sizeimage, &capture) < 0))) {
		perror("map V4L2 buffer");
		goto out;
	}

	output_size = output_format.plane_fmt[0].sizeimage;
	if (output_size > output.length) {
		fprintf(stderr, "driver returned an undersized output buffer\n");
		goto out;
	}
	if (sync_dmabuf(&output, DMA_BUF_SYNC_START | DMA_BUF_SYNC_WRITE) < 0) {
		perror("start DMA-BUF CPU write");
		goto out;
	}
	fill_input(output.address, output_format.pixelformat,
		   output_format.width, output_format.height,
		   output_format.plane_fmt[0].bytesperline, 0, pattern);
	if (sync_dmabuf(&output, DMA_BUF_SYNC_END | DMA_BUF_SYNC_WRITE) < 0) {
		perror("finish DMA-BUF CPU write");
		goto out;
	}

	output_fd = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC,
			  0644);
	if (output_fd < 0) {
		perror("open H.264 output");
		goto out;
	}

	if (queue_buffer(fd, capture_type, memory, &capture, 0) < 0 ||
	    queue_buffer(fd, output_type, memory, &output, output_size) < 0 ||
	    stream(fd, capture_type, true) < 0) {
		perror("start V4L2 stream");
		goto out;
	}
	clock_gettime(CLOCK_MONOTONIC, &started);
	if (stream(fd, output_type, true) < 0) {
		perror("start V4L2 stream");
		goto stop;
	}

	poll_fd.fd = fd;
	poll_fd.events = POLLIN | POLLOUT | POLLERR;
	while (frame_index < frames) {
		while (!output_done || !capture_done) {
			if (poll(&poll_fd, 1, 10000) <= 0) {
				perror("poll");
				goto stop;
			}
			if (!capture_done &&
			    dequeue_buffer(fd, capture_type, memory, &capture_size,
					   &capture_flags) == 0)
				capture_done = true;
			else if (errno != EAGAIN && !capture_done) {
				fprintf(stderr, "frame %u: ", frame_index);
				perror("dequeue capture");
				goto stop;
			}
			if (!output_done &&
			    dequeue_buffer(fd, output_type, memory, &ignored, NULL) == 0)
				output_done = true;
			else if (errno != EAGAIN && !output_done) {
				fprintf(stderr, "frame %u: ", frame_index);
				perror("dequeue output");
				goto stop;
			}
		}

		if (!capture_size || capture_size > capture.length) {
			fprintf(stderr, "invalid capture payload %zu\n",
				capture_size);
			goto stop;
		}
		if (sync_dmabuf(&capture,
				 DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ) < 0) {
			perror("start DMA-BUF CPU read");
			goto stop;
		}
		if (write_all(output_fd, capture.address, capture_size) < 0) {
			perror("write H.264 output");
			goto stop;
		}
		filler_size += find_filler_size(capture.address, capture_size);
		if (find_nal(capture.address, capture_size, 5)) {
			idr_frames++;
			if (!find_nal(capture.address, capture_size, 7) ||
			    !find_nal(capture.address, capture_size, 8) ||
			    !(capture_flags & V4L2_BUF_FLAG_KEYFRAME)) {
				fprintf(stderr,
					"frame %u: incomplete or incorrectly flagged IDR access unit\n",
					frame_index);
				goto stop;
			}
		} else if (find_nal(capture.address, capture_size, 1)) {
			p_frames++;
			if (!(capture_flags & V4L2_BUF_FLAG_PFRAME)) {
				fprintf(stderr,
					"frame %u: P access unit lacks PFRAME flag\n",
					frame_index);
				goto stop;
			}
		} else {
			fprintf(stderr,
				"frame %u: %zu-byte payload has no IDR or non-IDR slice\n",
				frame_index, capture_size);
			goto stop;
		}
		if (sync_dmabuf(&capture,
				 DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ) < 0) {
			perror("finish DMA-BUF CPU read");
			goto stop;
		}

		total_size += capture_size;
		frame_index++;
		if (frame_index == switch_frame) {
			switch_size = total_size;
			if (set_control(fd, V4L2_CID_MPEG_VIDEO_BITRATE,
					switch_bitrate) < 0 ||
			    set_control(fd, V4L2_CID_MPEG_VIDEO_BITRATE_PEAK,
					peak_bitrate > switch_bitrate ?
					peak_bitrate : switch_bitrate) < 0) {
				perror("switch bitrate");
				goto stop;
			}
		}
		if (frame_index == frames)
			break;
		if (frame_index == force_frame &&
		    set_control(fd, V4L2_CID_MPEG_VIDEO_FORCE_KEY_FRAME, 0) < 0) {
			perror("force key frame");
			goto stop;
		}
		/* A flat frame is invariant.  Reuse the initial DMA-BUF contents so
		 * this mode measures encoder throughput instead of CPU pattern-fill
		 * throughput, which is especially expensive for packed YUYV.
		 */
		if (pattern != PATTERN_FLAT) {
			if (sync_dmabuf(&output,
					 DMA_BUF_SYNC_START | DMA_BUF_SYNC_WRITE) < 0) {
				perror("start DMA-BUF CPU write");
				goto stop;
			}
			fill_input(output.address, output_format.pixelformat,
				   output_format.width, output_format.height,
				   output_format.plane_fmt[0].bytesperline,
				   frame_index, pattern);
			if (sync_dmabuf(&output,
					 DMA_BUF_SYNC_END | DMA_BUF_SYNC_WRITE) < 0) {
				perror("finish DMA-BUF CPU write");
				goto stop;
			}
		}

		output_done = false;
		capture_done = false;
		capture_size = 0;
		if (queue_buffer(fd, capture_type, memory, &capture, 0) < 0 ||
		    queue_buffer(fd, output_type, memory, &output,
				 output_size) < 0) {
			perror("queue next V4L2 frame");
			goto stop;
		}
	}
	clock_gettime(CLOCK_MONOTONIC, &finished);
	elapsed = finished.tv_sec - started.tv_sec +
		(finished.tv_nsec - started.tv_nsec) / 1000000000.0;
	reported_target = bitrate;
	if (switch_frame != UINT32_MAX)
		reported_target =
			((double)bitrate * switch_frame +
			 (double)switch_bitrate * (frames - switch_frame)) / frames;
	printf("encoded %u %ux%u %s %s frame(s) via %s at QP %u "
	       "(%u IDR, %u P) to %zu bytes "
	       "of Annex-B H.264 in %.6f s (%.2f fps, %.2f Mpixel/s)\n",
	       frames, output_format.width, output_format.height,
	       pattern_name(pattern),
	       output_format.pixelformat == V4L2_PIX_FMT_YUYV ? "YUYV" :
	       "NV12",
	       memory == V4L2_MEMORY_DMABUF ? "DMA-BUF" : "MMAP", qp,
	       idr_frames, p_frames, total_size, elapsed, frames / elapsed,
	       frames * output_format.width * output_format.height /
	       elapsed / 1000000.0);
	printf("rate control: %s, %u fps, average target %.0f bit/s, "
	       "initial peak %u bit/s, "
	       "stream %.0f bit/s, filler %zu bytes (%.1f%%)\n",
	       rate_control_name(rc_mode), fps, reported_target, peak_bitrate,
	       total_size * 8.0 * fps / frames, filler_size,
	       total_size ? filler_size * 100.0 / total_size : 0.0);
	if (switch_frame != UINT32_MAX)
		printf("runtime switch at frame %u: first segment %.0f bit/s, "
		       "second segment %.0f bit/s (new target %u bit/s)\n",
		       switch_frame, switch_size * 8.0 * fps / switch_frame,
		       (total_size - switch_size) * 8.0 * fps /
		       (frames - switch_frame), switch_bitrate);
	ret = 0;

stop:
	stream(fd, output_type, false);
	stream(fd, capture_type, false);
out:
	if (output_fd >= 0)
		close(output_fd);
	if (capture.address && capture.address != MAP_FAILED)
		munmap(capture.address, capture.length);
	if (output.address && output.address != MAP_FAILED)
		munmap(output.address, output.length);
	if (capture.dmabuf_fd >= 0)
		close(capture.dmabuf_fd);
	if (output.dmabuf_fd >= 0)
		close(output.dmabuf_fd);
	if (fd >= 0)
		close(fd);
	return ret;
}
