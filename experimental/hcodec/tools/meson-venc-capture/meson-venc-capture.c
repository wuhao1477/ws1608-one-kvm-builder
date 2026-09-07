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

#define INPUT_BUFFER_COUNT 4U
#define CODED_BUFFER_COUNT 2U

struct dmabuf {
	void *address;
	size_t length;
	int fd;
};

enum rate_control_mode {
	RATE_CONTROL_CQ,
	RATE_CONTROL_VBR,
	RATE_CONTROL_CBR,
};

static void usage(FILE *stream, const char *program)
{
	fprintf(stream,
		"Usage: %s CAPTURE ENCODER OUTPUT.h264 "
		"[WIDTH HEIGHT FPS FRAMES GOP [RC_MODE BITRATE PEAK_BITRATE]]\n"
		"Defaults: 1280 720 30 1800 30 cq 4000000 8000000\n"
		"Uses separate CMA DMA-BUF pools and one CPU YUYV copy.\n",
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

static int xioctl(int fd, unsigned long request, void *argument)
{
	int ret;

	do {
		ret = ioctl(fd, request, argument);
	} while (ret < 0 && errno == EINTR);
	return ret;
}

static int set_control(int fd, uint32_t id, int32_t value)
{
	struct v4l2_control control = {
		.id = id,
		.value = value,
	};

	return xioctl(fd, VIDIOC_S_CTRL, &control);
}

static int configure_rate_control(int fd, enum rate_control_mode mode,
				  uint32_t bitrate, uint32_t peak_bitrate,
				  uint32_t fps)
{
	struct v4l2_streamparm parm = {
		.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE,
	};
	int32_t v4l2_mode = V4L2_MPEG_VIDEO_BITRATE_MODE_CQ;

	if (mode == RATE_CONTROL_VBR)
		v4l2_mode = V4L2_MPEG_VIDEO_BITRATE_MODE_VBR;
	else if (mode == RATE_CONTROL_CBR)
		v4l2_mode = V4L2_MPEG_VIDEO_BITRATE_MODE_CBR;
	parm.parm.output.timeperframe.numerator = 1;
	parm.parm.output.timeperframe.denominator = fps;
	if (xioctl(fd, VIDIOC_S_PARM, &parm) < 0 ||
	    set_control(fd, V4L2_CID_MPEG_VIDEO_BITRATE, bitrate) < 0 ||
	    set_control(fd, V4L2_CID_MPEG_VIDEO_BITRATE_PEAK,
			peak_bitrate) < 0 ||
	    set_control(fd, V4L2_CID_MPEG_VIDEO_FRAME_RC_ENABLE, 1) < 0 ||
	    set_control(fd, V4L2_CID_MPEG_VIDEO_BITRATE_MODE, v4l2_mode) < 0)
		return -1;
	return 0;
}

static int stream(int fd, enum v4l2_buf_type type, bool on)
{
	return xioctl(fd, on ? VIDIOC_STREAMON : VIDIOC_STREAMOFF, &type);
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

static int allocate_dmabuf(size_t size, bool map, struct dmabuf *buffer)
{
	struct dma_heap_allocation_data allocation = {
		.len = size,
		.fd_flags = O_RDWR | O_CLOEXEC,
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

	buffer->fd = allocation.fd;
	buffer->length = size;
	buffer->address = NULL;
	if (!map)
		return 0;
	buffer->address = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED,
			       buffer->fd, 0);
	return buffer->address == MAP_FAILED ? -1 : 0;
}

static int sync_dmabuf(const struct dmabuf *buffer, uint64_t flags)
{
	struct dma_buf_sync sync = { .flags = flags };

	return xioctl(buffer->fd, DMA_BUF_IOCTL_SYNC, &sync);
}

static int request_buffers(int fd, enum v4l2_buf_type type,
			   uint32_t count)
{
	struct v4l2_requestbuffers request = {
		.count = count,
		.type = type,
		.memory = V4L2_MEMORY_DMABUF,
	};

	if (xioctl(fd, VIDIOC_REQBUFS, &request) < 0)
		return -1;
	if (request.count < count) {
		errno = ENOMEM;
		return -1;
	}
	return 0;
}

static int set_capture_format(int fd, uint32_t width, uint32_t height,
			      uint32_t fps, struct v4l2_pix_format *pix)
{
	struct v4l2_streamparm parm = {
		.type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
	};
	struct v4l2_format format = {
		.type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
	};

	format.fmt.pix.width = width;
	format.fmt.pix.height = height;
	format.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
	format.fmt.pix.field = V4L2_FIELD_NONE;
	if (xioctl(fd, VIDIOC_S_FMT, &format) < 0)
		return -1;
	if (format.fmt.pix.width != width || format.fmt.pix.height != height ||
	    format.fmt.pix.pixelformat != V4L2_PIX_FMT_YUYV) {
		errno = EINVAL;
		return -1;
	}

	parm.parm.capture.timeperframe.numerator = 1;
	parm.parm.capture.timeperframe.denominator = fps;
	if (xioctl(fd, VIDIOC_S_PARM, &parm) < 0)
		return -1;
	if (!parm.parm.capture.timeperframe.numerator ||
	    parm.parm.capture.timeperframe.denominator /
	    parm.parm.capture.timeperframe.numerator != fps) {
		errno = ERANGE;
		return -1;
	}

	*pix = format.fmt.pix;
	return 0;
}

static int set_encoder_format(int fd, enum v4l2_buf_type type,
			      uint32_t fourcc, uint32_t width,
			      uint32_t height,
			      struct v4l2_pix_format_mplane *pix)
{
	struct v4l2_format format = {
		.type = type,
	};

	format.fmt.pix_mp.width = width;
	format.fmt.pix_mp.height = height;
	format.fmt.pix_mp.pixelformat = fourcc;
	format.fmt.pix_mp.field = V4L2_FIELD_NONE;
	format.fmt.pix_mp.num_planes = 1;
	if (xioctl(fd, VIDIOC_S_FMT, &format) < 0)
		return -1;
	if (format.fmt.pix_mp.width != width ||
	    format.fmt.pix_mp.height != height ||
	    format.fmt.pix_mp.pixelformat != fourcc) {
		errno = EINVAL;
		return -1;
	}

	*pix = format.fmt.pix_mp;
	return 0;
}

static int queue_capture(int fd, uint32_t index, const struct dmabuf *buffer)
{
	struct v4l2_buffer vbuf = {
		.type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
		.memory = V4L2_MEMORY_DMABUF,
		.index = index,
		.length = buffer->length,
	};

	vbuf.m.fd = buffer->fd;
	return xioctl(fd, VIDIOC_QBUF, &vbuf);
}

static int dequeue_capture(int fd, struct v4l2_buffer *buffer)
{
	memset(buffer, 0, sizeof(*buffer));
	buffer->type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	buffer->memory = V4L2_MEMORY_DMABUF;
	return xioctl(fd, VIDIOC_DQBUF, buffer);
}

static int queue_encoder(int fd, enum v4l2_buf_type type, uint32_t index,
			 const struct dmabuf *buffer, size_t bytesused,
			 const struct timeval *timestamp)
{
	struct v4l2_plane plane = {
		.bytesused = bytesused,
		.length = buffer->length,
	};
	struct v4l2_buffer vbuf = {
		.type = type,
		.memory = V4L2_MEMORY_DMABUF,
		.index = index,
		.length = 1,
		.m.planes = &plane,
	};

	plane.m.fd = buffer->fd;
	if (timestamp)
		vbuf.timestamp = *timestamp;
	return xioctl(fd, VIDIOC_QBUF, &vbuf);
}

static int dequeue_encoder(int fd, enum v4l2_buf_type type,
			   struct v4l2_buffer *buffer,
			   struct v4l2_plane *plane)
{
	memset(buffer, 0, sizeof(*buffer));
	memset(plane, 0, sizeof(*plane));
	buffer->type = type;
	buffer->memory = V4L2_MEMORY_DMABUF;
	buffer->length = 1;
	buffer->m.planes = plane;
	return xioctl(fd, VIDIOC_DQBUF, buffer);
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

static void release_dmabuf(struct dmabuf *buffer)
{
	if (buffer->address && buffer->address != MAP_FAILED)
		munmap(buffer->address, buffer->length);
	if (buffer->fd >= 0)
		close(buffer->fd);
	buffer->address = NULL;
	buffer->fd = -1;
}

int main(int argc, char **argv)
{
	struct dmabuf capture_input[INPUT_BUFFER_COUNT];
	struct dmabuf encoder_input[INPUT_BUFFER_COUNT];
	struct dmabuf coded[CODED_BUFFER_COUNT];
	struct v4l2_pix_format capture_format;
	struct v4l2_pix_format_mplane encoder_output;
	struct v4l2_pix_format_mplane encoder_capture;
	struct pollfd poll_fds[2];
	enum v4l2_buf_type capture_type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	enum v4l2_buf_type output_type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	enum v4l2_buf_type coded_type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	struct timespec started;
	struct timespec finished;
	uint32_t width = 1280;
	uint32_t height = 720;
	uint32_t fps = 30;
	uint32_t frames = 1800;
	uint32_t gop = 30;
	uint32_t bitrate = 4000000;
	uint32_t peak_bitrate = 8000000;
	uint32_t submitted = 0;
	uint32_t processed = 0;
	uint32_t completed = 0;
	uint32_t encode_errors = 0;
	uint32_t idr_frames = 0;
	uint32_t p_frames = 0;
	uint32_t first_sequence = UINT32_MAX;
	uint32_t last_sequence = 0;
	size_t total_size = 0;
	size_t filler_size = 0;
	double elapsed;
	bool capture_streaming = false;
	bool encoder_output_streaming = false;
	bool encoder_capture_streaming = false;
	enum rate_control_mode rc_mode = RATE_CONTROL_CQ;
	unsigned int i;
	int output_fd = -1;
	int capture_fd = -1;
	int encoder_fd = -1;
	int ret = 1;

	for (i = 0; i < INPUT_BUFFER_COUNT; i++) {
		capture_input[i].fd = -1;
		encoder_input[i].fd = -1;
	}
	for (i = 0; i < CODED_BUFFER_COUNT; i++)
		coded[i].fd = -1;

	if (argc == 2 && !strcmp(argv[1], "--help")) {
		usage(stdout, argv[0]);
		return 0;
	}
	if (argc != 4 && argc != 9 && argc != 12) {
		usage(stderr, argv[0]);
		return 2;
	}
	if (argc >= 9) {
		width = strtoul(argv[4], NULL, 0);
		height = strtoul(argv[5], NULL, 0);
		fps = strtoul(argv[6], NULL, 0);
		frames = strtoul(argv[7], NULL, 0);
		gop = strtoul(argv[8], NULL, 0);
	}
	if (argc == 12) {
		if (parse_rate_control(argv[9], &rc_mode) < 0) {
			fprintf(stderr, "RC_MODE must be cq, vbr or cbr\n");
			return 2;
		}
		bitrate = strtoul(argv[10], NULL, 0);
		peak_bitrate = strtoul(argv[11], NULL, 0);
	}
	if (!width || !height || !fps || !frames || !gop) {
		fprintf(stderr, "dimensions, FPS, frames and GOP must be nonzero\n");
		return 2;
	}
	if (!bitrate || !peak_bitrate) {
		fprintf(stderr, "bitrates must be nonzero\n");
		return 2;
	}

	capture_fd = open(argv[1], O_RDWR | O_NONBLOCK | O_CLOEXEC);
	if (capture_fd < 0) {
		perror("open capture device");
		goto out;
	}
	encoder_fd = open(argv[2], O_RDWR | O_NONBLOCK | O_CLOEXEC);
	if (encoder_fd < 0) {
		perror("open encoder device");
		goto out;
	}
	output_fd = open(argv[3], O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC,
			 0644);
	if (output_fd < 0) {
		perror("open H.264 output");
		goto out;
	}

	if (set_capture_format(capture_fd, width, height, fps,
			       &capture_format) < 0) {
		perror("configure YUYV capture");
		goto out;
	}
	if (set_control(encoder_fd, V4L2_CID_MPEG_VIDEO_GOP_SIZE, gop) < 0 ||
	    configure_rate_control(encoder_fd, rc_mode, bitrate,
				   peak_bitrate, fps) < 0 ||
	    set_encoder_format(encoder_fd, output_type, V4L2_PIX_FMT_YUYV,
			       width, height, &encoder_output) < 0 ||
	    set_encoder_format(encoder_fd, coded_type, V4L2_PIX_FMT_H264,
			       width, height, &encoder_capture) < 0) {
		perror("configure encoder");
		goto out;
	}
	if (capture_format.sizeimage != encoder_output.plane_fmt[0].sizeimage) {
		fprintf(stderr, "capture/encoder size mismatch: %u/%u\n",
			capture_format.sizeimage,
			encoder_output.plane_fmt[0].sizeimage);
		goto out;
	}

	for (i = 0; i < INPUT_BUFFER_COUNT; i++) {
		if (allocate_dmabuf(capture_format.sizeimage, true,
				     &capture_input[i]) < 0 ||
		    allocate_dmabuf(encoder_output.plane_fmt[0].sizeimage, true,
				     &encoder_input[i]) < 0) {
			perror("allocate capture/encoder DMA-BUF");
			goto out;
		}
	}
	for (i = 0; i < CODED_BUFFER_COUNT; i++) {
		if (allocate_dmabuf(encoder_capture.plane_fmt[0].sizeimage, true,
				     &coded[i]) < 0) {
			perror("allocate coded DMA-BUF");
			goto out;
		}
	}

	if (request_buffers(capture_fd, capture_type, INPUT_BUFFER_COUNT) < 0 ||
	    request_buffers(encoder_fd, output_type, INPUT_BUFFER_COUNT) < 0 ||
	    request_buffers(encoder_fd, coded_type, CODED_BUFFER_COUNT) < 0) {
		perror("request imported buffers");
		goto out;
	}
	for (i = 0; i < INPUT_BUFFER_COUNT; i++) {
		if (queue_capture(capture_fd, i, &capture_input[i]) < 0) {
			perror("queue capture DMA-BUF");
			goto out;
		}
	}
	for (i = 0; i < CODED_BUFFER_COUNT; i++) {
		if (queue_encoder(encoder_fd, coded_type, i, &coded[i], 0,
				  NULL) < 0) {
			perror("queue coded DMA-BUF");
			goto out;
		}
	}

	if (stream(encoder_fd, coded_type, true) < 0) {
		perror("start encoder CAPTURE");
		goto out;
	}
	encoder_capture_streaming = true;
	if (stream(encoder_fd, output_type, true) < 0) {
		perror("start encoder OUTPUT");
		goto out;
	}
	encoder_output_streaming = true;
	if (stream(capture_fd, capture_type, true) < 0) {
		perror("start USB capture");
		goto out;
	}
	capture_streaming = true;
	clock_gettime(CLOCK_MONOTONIC, &started);

	poll_fds[0].fd = capture_fd;
	poll_fds[0].events = POLLIN | POLLERR;
	poll_fds[1].fd = encoder_fd;
	poll_fds[1].events = POLLIN | POLLOUT | POLLERR;
	while (processed < frames) {
		struct v4l2_buffer vbuf;
		struct v4l2_plane plane;

		if (poll(poll_fds, 2, 10000) <= 0) {
			perror("poll capture/encoder");
			goto out;
		}

		if (submitted < frames && poll_fds[0].revents & POLLIN) {
			if (dequeue_capture(capture_fd, &vbuf) == 0) {
				if (getenv("MESON_CAPTURE_DEBUG"))
					fprintf(stderr,
						"USB submit %u: sequence %u index %u bytes %u flags %#x\n",
						submitted, vbuf.sequence, vbuf.index,
						vbuf.bytesused, vbuf.flags);
				if (vbuf.index >= INPUT_BUFFER_COUNT ||
				    vbuf.bytesused < encoder_output.plane_fmt[0].sizeimage) {
					fprintf(stderr, "invalid capture buffer %u/%u\n",
						vbuf.index, vbuf.bytesused);
					goto out;
				}
				if (first_sequence == UINT32_MAX)
					first_sequence = vbuf.sequence;
				last_sequence = vbuf.sequence;
				if (sync_dmabuf(&capture_input[vbuf.index],
						 DMA_BUF_SYNC_START |
						 DMA_BUF_SYNC_READ) < 0 ||
				    sync_dmabuf(&encoder_input[vbuf.index],
						 DMA_BUF_SYNC_START |
						 DMA_BUF_SYNC_WRITE) < 0) {
					perror("start capture copy synchronization");
					goto out;
				}
				memcpy(encoder_input[vbuf.index].address,
				       capture_input[vbuf.index].address,
				       encoder_output.plane_fmt[0].sizeimage);
				if (sync_dmabuf(&encoder_input[vbuf.index],
						 DMA_BUF_SYNC_END |
						 DMA_BUF_SYNC_WRITE) < 0 ||
				    sync_dmabuf(&capture_input[vbuf.index],
						 DMA_BUF_SYNC_END |
						 DMA_BUF_SYNC_READ) < 0) {
					perror("finish capture copy synchronization");
					goto out;
				}
				if (queue_encoder(encoder_fd, output_type, vbuf.index,
						  &encoder_input[vbuf.index],
						  vbuf.bytesused,
						  &vbuf.timestamp) < 0) {
					perror("queue captured frame to encoder");
					goto out;
				}
				submitted++;
			} else if (errno != EAGAIN) {
				perror("dequeue USB capture");
				goto out;
			}
		}

		if (poll_fds[1].revents & POLLOUT) {
			while (dequeue_encoder(encoder_fd, output_type, &vbuf,
					       &plane) == 0) {
				if (vbuf.index >= INPUT_BUFFER_COUNT) {
					fprintf(stderr, "invalid encoder OUTPUT index\n");
					goto out;
				}
				if (submitted < frames &&
				    queue_capture(capture_fd, vbuf.index,
						  &capture_input[vbuf.index]) < 0) {
					perror("return DMA-BUF to USB capture");
					goto out;
				}
			}
			if (errno != EAGAIN) {
				perror("dequeue encoder OUTPUT");
				goto out;
			}
		}

		if (poll_fds[1].revents & POLLIN) {
			while (dequeue_encoder(encoder_fd, coded_type, &vbuf,
					       &plane) == 0) {
				if (vbuf.index >= CODED_BUFFER_COUNT ||
				    plane.bytesused > coded[vbuf.index].length) {
					fprintf(stderr, "invalid coded buffer metadata\n");
					goto out;
				}
				if (!plane.bytesused ||
				    vbuf.flags & V4L2_BUF_FLAG_ERROR) {
					fprintf(stderr,
						"dropping encoder error at input frame %u: index %u, bytes %u, flags %#x\n",
						processed, vbuf.index,
						plane.bytesused, vbuf.flags);
					processed++;
					encode_errors++;
					if (processed < frames &&
					    queue_encoder(encoder_fd, coded_type,
							  vbuf.index,
							  &coded[vbuf.index], 0,
							  NULL) < 0) {
						perror("requeue coded DMA-BUF after error");
						goto out;
					}
					continue;
				}
				if (sync_dmabuf(&coded[vbuf.index],
						 DMA_BUF_SYNC_START |
						 DMA_BUF_SYNC_READ) < 0) {
					perror("start coded DMA-BUF read");
					goto out;
				}
				if (write_all(output_fd, coded[vbuf.index].address,
					      plane.bytesused) < 0) {
					perror("write H.264 output");
					goto out;
				}
				filler_size +=
					find_filler_size(coded[vbuf.index].address,
							 plane.bytesused);
				if (find_nal(coded[vbuf.index].address,
					     plane.bytesused, 5))
					idr_frames++;
				else if (find_nal(coded[vbuf.index].address,
						  plane.bytesused, 1))
					p_frames++;
				else {
					fprintf(stderr, "coded frame has no slice NAL\n");
					goto out;
				}
				if (sync_dmabuf(&coded[vbuf.index],
						 DMA_BUF_SYNC_END |
						 DMA_BUF_SYNC_READ) < 0) {
					perror("finish coded DMA-BUF read");
					goto out;
				}
				total_size += plane.bytesused;
				completed++;
				processed++;
				if (processed < frames &&
				    queue_encoder(encoder_fd, coded_type, vbuf.index,
						  &coded[vbuf.index], 0, NULL) < 0) {
					perror("requeue coded DMA-BUF");
					goto out;
				}
				if (processed == frames)
					break;
			}
			if (processed < frames && errno != EAGAIN) {
				perror("dequeue encoder CAPTURE");
				goto out;
			}
		}
	}

	clock_gettime(CLOCK_MONOTONIC, &finished);
	elapsed = finished.tv_sec - started.tv_sec +
		(finished.tv_nsec - started.tv_nsec) / 1000000000.0;
	printf("captured %u and encoded %u %ux%u YUYV frame(s) "
	       "through one CPU copy at %u fps "
	       "(%u IDR, %u P, %u dropped) to %zu bytes in %.6f s "
	       "(%.2f input fps); "
	       "USB sequence %u..%u (%u observed gap(s))\n",
	       frames, completed, width, height, fps, idr_frames, p_frames,
	       encode_errors, total_size, elapsed, frames / elapsed,
	       first_sequence, last_sequence,
	       last_sequence - first_sequence + 1 - frames);
	printf("rate control: %s, target %u bit/s, peak %u bit/s, "
	       "stream %.0f bit/s, filler %zu bytes (%.1f%%)\n",
	       rate_control_name(rc_mode), bitrate, peak_bitrate,
	       completed ? total_size * 8.0 * fps / completed : 0.0,
	       filler_size,
	       total_size ? filler_size * 100.0 / total_size : 0.0);
	ret = 0;

out:
	if (capture_streaming)
		stream(capture_fd, capture_type, false);
	if (encoder_output_streaming)
		stream(encoder_fd, output_type, false);
	if (encoder_capture_streaming)
		stream(encoder_fd, coded_type, false);
	if (output_fd >= 0)
		close(output_fd);
	for (i = 0; i < CODED_BUFFER_COUNT; i++)
		release_dmabuf(&coded[i]);
	for (i = 0; i < INPUT_BUFFER_COUNT; i++) {
		release_dmabuf(&encoder_input[i]);
		release_dmabuf(&capture_input[i]);
	}
	if (encoder_fd >= 0)
		close(encoder_fd);
	if (capture_fd >= 0)
		close(capture_fd);
	return ret;
}
