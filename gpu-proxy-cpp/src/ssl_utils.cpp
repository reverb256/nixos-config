#include "ssl_utils.hpp"
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <netdb.h>

namespace gpu_proxy {

TLSConnection::TLSConnection(const std::string& host, uint16_t port)
    : host_(host), port_(port) {}

TLSConnection::~TLSConnection() {
    disconnect();
}

bool TLSConnection::create_ssl_context() {
    // Create SSL context (client method)
    const SSL_METHOD* method = TLS_client_method();
    ctx_ = SSL_CTX_new(method);
    if (!ctx_) {
        return false;
    }

    // Set minimum protocol version to TLS 1.2
    SSL_CTX_set_min_proto_version(ctx_, TLS1_2_VERSION);

    // Set cipher list for maximum compatibility
    // This matches xmrig-proxy settings
    if (SSL_CTX_set_cipher_list(ctx_, "DEFAULT:@SECLEVEL=0") <= 0) {
        SSL_CTX_free(ctx_);
        ctx_ = nullptr;
        return false;
    }

    // Disable certificate verification (pools use self-signed)
    SSL_CTX_set_verify(ctx_, SSL_VERIFY_NONE, nullptr);

    return true;
}

bool TLSConnection::perform_ssl_handshake() {
    ssl_ = SSL_new(ctx_);
    if (!ssl_) {
        return false;
    }

    // Set SNI hostname
    SSL_set_tlsext_host_name(ssl_, host_.c_str());

    // Create SSL file descriptor
    if (!SSL_set_fd(ssl_, socket_fd_)) {
        SSL_free(ssl_);
        ssl_ = nullptr;
        return false;
    }

    // Perform SSL handshake
    int ret = SSL_connect(ssl_);
    if (ret != 1) {
        int err = SSL_get_error(ssl_, ret);
        // Handle SSL_ERROR_WANT_READ/WRITE properly in non-blocking mode
        // For blocking mode, ret == 1 means success
        SSL_free(ssl_);
        ssl_ = nullptr;
        return false;
    }

    return true;
}

bool TLSConnection::connect() {
    // Create socket
    socket_fd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (socket_fd_ < 0) {
        return false;
    }

    // Set socket to blocking mode (simpler for initial implementation)
    int flags = fcntl(socket_fd_, F_GETFL, 0);
    fcntl(socket_fd_, F_SETFL, flags & ~O_NONBLOCK);

    // Connect to host - resolve via getaddrinfo (more modern than gethostbyname)
    struct addrinfo hints{}, *result;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    int ret = getaddrinfo(host_.c_str(), nullptr, &hints, &result);
    if (ret != 0) {
        ::close(socket_fd_);
        socket_fd_ = -1;
        return false;
    }

    // Set port
    ((struct sockaddr_in*)(result->ai_addr))->sin_port = htons(port_);

    if (::connect(socket_fd_, result->ai_addr, result->ai_addrlen) < 0) {
        freeaddrinfo(result);
        ::close(socket_fd_);
        socket_fd_ = -1;
        return false;
    }
    freeaddrinfo(result);

    // Create SSL context and perform handshake
    if (!create_ssl_context()) {
        ::close(socket_fd_);
        socket_fd_ = -1;
        return false;
    }

    if (!perform_ssl_handshake()) {
        SSL_CTX_free(ctx_);
        ctx_ = nullptr;
        ::close(socket_fd_);
        socket_fd_ = -1;
        return false;
    }

    connected_ = true;
    return true;
}

void TLSConnection::disconnect() {
    if (ssl_) {
        SSL_shutdown(ssl_);
        SSL_free(ssl_);
        ssl_ = nullptr;
    }
    if (ctx_) {
        SSL_CTX_free(ctx_);
        ctx_ = nullptr;
    }
    if (socket_fd_ >= 0) {
        ::close(socket_fd_);
        socket_fd_ = -1;
    }
    connected_ = false;
}

bool TLSConnection::send_line(const std::string& line) {
    if (!connected_) return false;

    std::string full_line = line + "\n";
    int sent = SSL_write(ssl_, full_line.c_str(), full_line.length());
    return sent == static_cast<int>(full_line.length());
}

std::string TLSConnection::recv_line(int timeout_sec) {
    if (!connected_) return "";

    std::string result;
    char buf[1024];

    while (true) {
        int received = SSL_read(ssl_, buf, sizeof(buf) - 1);
        if (received <= 0) {
            int err = SSL_get_error(ssl_, received);
            if (err == SSL_ERROR_ZERO_RETURN) {
                // Clean shutdown
                break;
            }
            if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
                // In non-blocking mode, would retry
                continue;
            }
            // Error
            break;
        }

        buf[received] = '\0';
        result += buf;

        // Check if we have a complete line
        if (result.find('\n') != std::string::npos) {
            break;
        }
    }

    // Trim at newline
    size_t newline_pos = result.find('\n');
    if (newline_pos != std::string::npos) {
        result = result.substr(0, newline_pos);
    }

    return result;
}

} // namespace gpu_proxy
