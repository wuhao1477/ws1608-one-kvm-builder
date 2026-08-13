#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <climits>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

namespace {
using AbiFn = int (*)();
using InitFn = long (*)(int, int, int, int, int, int, int);
using EncodeFn = int (*)(long, int, unsigned char*, int, unsigned char*, int);
using DestroyFn = int (*)(long);

struct Options {
    std::string library = "libvpcodec.so";
    std::string input;
    std::string output;
    int width = 0;
    int height = 0;
    int fps = 0;
    int bitrate = 0;
    int frames = 0;
    bool abi_check = false;
};

struct Api {
    void* library = nullptr;
    AbiFn abi = nullptr;
    InitFn init = nullptr;
    EncodeFn encode = nullptr;
    DestroyFn destroy = nullptr;

    Api() = default;
    Api(const Api&) = delete;
    Api& operator=(const Api&) = delete;
    Api(Api&& other) noexcept
        : library(other.library), abi(other.abi), init(other.init),
          encode(other.encode), destroy(other.destroy) {
        other.library = nullptr;
    }

    ~Api() {
        if (library)
            dlclose(library);
    }
};

[[noreturn]] void fail(const std::string& message) {
    std::fprintf(stderr, "amlenc-m8-diag: %s\n", message.c_str());
    std::exit(1);
}

int parse_positive(const char* value, const char* option) {
    char* end = nullptr;
    errno = 0;
    long parsed = std::strtol(value, &end, 10);
    if (errno || !end || *end || parsed <= 0 || parsed > INT_MAX)
        fail(std::string("invalid value for ") + option);
    return static_cast<int>(parsed);
}

Options parse_options(int argc, char** argv) {
    Options options;
    if (argc == 3 && std::strcmp(argv[1], "--abi-check") == 0) {
        options.abi_check = true;
        options.library = argv[2];
        return options;
    }
    for (int index = 1; index < argc; index += 2) {
        if (index + 1 >= argc)
            fail("every option requires a value");
        const std::string option = argv[index];
        const char* value = argv[index + 1];
        if (option == "--library") options.library = value;
        else if (option == "--input") options.input = value;
        else if (option == "--output") options.output = value;
        else if (option == "--width") options.width = parse_positive(value, argv[index]);
        else if (option == "--height") options.height = parse_positive(value, argv[index]);
        else if (option == "--fps") options.fps = parse_positive(value, argv[index]);
        else if (option == "--bitrate") options.bitrate = parse_positive(value, argv[index]);
        else if (option == "--frames") options.frames = parse_positive(value, argv[index]);
        else fail("unknown option: " + option);
    }
    if (options.input.empty() || options.output.empty() || !options.width ||
        !options.height || !options.fps || !options.bitrate || !options.frames)
        fail("required: --input --width --height --fps --bitrate --frames --output");
    return options;
}

template <typename T>
T load_symbol(void* library, const char* name) {
    dlerror();
    void* symbol = dlsym(library, name);
    const char* error = dlerror();
    if (error)
        fail(std::string("missing ABI symbol ") + name + ": " + error);
    return reinterpret_cast<T>(symbol);
}

Api load_api(const std::string& path) {
    Api api;
    api.library = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!api.library)
        fail(std::string("cannot load library: ") + dlerror());
    api.abi = load_symbol<AbiFn>(api.library, "one_kvm_amlenc_abi_version");
    api.init = load_symbol<InitFn>(api.library, "vl_video_encoder_init");
    api.encode = load_symbol<EncodeFn>(api.library, "vl_video_encoder_encode");
    api.destroy = load_symbol<DestroyFn>(api.library, "vl_video_encoder_destory");
    if (api.abi() != 1)
        fail("One-KVM AMLENC ABI version is not 1");
    return api;
}

size_t checked_frame_size(const Options& options) {
    const size_t width = static_cast<size_t>(options.width);
    const size_t height = static_cast<size_t>(options.height);
    if (height && width > SIZE_MAX / height)
        fail("NV12 frame size overflow");
    const size_t pixels = width * height;
    if (pixels > SIZE_MAX / 3)
        fail("NV12 frame size overflow");
    return pixels * 3 / 2;
}

bool validate_input_size(const Options& options, size_t frame_size) {
    if (static_cast<size_t>(options.frames) > SIZE_MAX / frame_size)
        fail("input size overflow");
    const size_t expected = frame_size * static_cast<size_t>(options.frames);
    struct stat info {};
    if (stat(options.input.c_str(), &info) != 0)
        fail(std::string("cannot stat input: ") + std::strerror(errno));
    if (info.st_size < 0)
        fail("input size is invalid");
    const size_t actual = static_cast<size_t>(info.st_size);
    if (actual != frame_size && actual != expected)
        fail("input size must contain one NV12 frame or exactly --frames frames");
    return actual == frame_size;
}

void scan_annex_b(const unsigned char* data, size_t size, bool& sps, bool& pps, bool& idr) {
    for (size_t i = 0; i + 4 < size; ++i) {
        size_t header = 0;
        if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) header = i + 3;
        else if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0 &&
                 data[i + 3] == 1) header = i + 4;
        if (!header || header >= size)
            continue;
        const unsigned type = data[header] & 0x1f;
        sps = sps || type == 7;
        pps = pps || type == 8;
        idr = idr || type == 5;
        i = header;
    }
}

void encode_file(const Options& options, Api& api) {
    if (access("/dev/amvenc_avc", R_OK | W_OK) != 0)
        fail(std::string("missing or inaccessible /dev/amvenc_avc: ") + std::strerror(errno));
    const size_t frame_size = checked_frame_size(options);
    if (options.width % 16 || options.height % 2)
        fail("NV12 width must be 16-aligned and height must be even");
    if (options.fps > INT_MAX / 2)
        fail("fps is too large for GOP calculation");
    const bool repeat_frame = validate_input_size(options, frame_size);
    std::ifstream input(options.input, std::ios::binary);
    std::ofstream output(options.output, std::ios::binary | std::ios::trunc);
    if (!input || !output)
        fail("cannot open input or output file");
    std::vector<unsigned char> frame_data(frame_size);
    const size_t output_capacity = std::max<size_t>(1024 * 1024, frame_size);
    if (output_capacity > INT_MAX)
        fail("output buffer is too large for vendor ABI");
    std::vector<unsigned char> packet(output_capacity);
    bool sps = false, pps = false, idr = false;
    long handle = api.init(4, options.width, options.height, options.fps,
                           options.bitrate, options.fps * 2, 1);
    if (handle <= 0)
        fail("encoder initialization failed");
    for (int frame = 0; frame < options.frames; ++frame) {
        if (repeat_frame) {
            input.clear();
            input.seekg(0);
        }
        if (!input.read(reinterpret_cast<char*>(frame_data.data()), frame_data.size())) {
            api.destroy(handle);
            fail("cannot read complete NV12 frame");
        }
        int length = api.encode(handle, frame == 0 ? 2 : 1, frame_data.data(),
                                static_cast<int>(output_capacity), packet.data(), 0);
        if (length < 0) {
            api.destroy(handle);
            fail("encoder call timeout or failure");
        }
        if (static_cast<size_t>(length) > packet.size()) {
            api.destroy(handle);
            fail("encoder returned an invalid output length");
        }
        output.write(reinterpret_cast<const char*>(packet.data()), length);
        scan_annex_b(packet.data(), static_cast<size_t>(length), sps, pps, idr);
    }
    if (api.destroy(handle) <= 0)
        fail("encoder destroy failed");
    output.flush();
    if (!output || output.tellp() <= 0)
        fail("zero output or empty output");
    if (!sps || !pps || !idr)
        fail("output is missing SPS, PPS, or IDR NAL units");
}
}  // namespace

int main(int argc, char** argv) {
    Options options = parse_options(argc, argv);
    Api api = load_api(options.library);
    if (options.abi_check) {
        std::puts("One-KVM AMLENC ABI v1");
        return 0;
    }
    encode_file(options, api);
    return 0;
}
