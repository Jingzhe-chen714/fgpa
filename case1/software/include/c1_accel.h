#ifndef C1_ACCEL_H
#define C1_ACCEL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Offsets implemented by rtl/control/c1_apb_csr.sv. */
enum {
    C1_REG_ID              = 0x000u,
    C1_REG_VERSION         = 0x004u,
    C1_REG_CAPABILITY      = 0x008u,
    C1_REG_CONTROL         = 0x010u,
    C1_REG_STATUS          = 0x014u,
    C1_REG_IRQ_ENABLE      = 0x018u,
    C1_REG_IRQ_STATUS      = 0x01cu,
    C1_REG_ERROR_CODE      = 0x020u,
    C1_REG_ERROR_ADDRESS   = 0x024u,
    C1_REG_IN_TABLE_LO     = 0x040u,
    C1_REG_IN_TABLE_HI     = 0x044u,
    C1_REG_OUT_TABLE_LO    = 0x048u,
    C1_REG_OUT_TABLE_HI    = 0x04cu,
    C1_REG_FRAME_SIZE      = 0x050u,
    C1_REG_IN_STRIDE       = 0x054u,
    C1_REG_OUT_STRIDE      = 0x058u,
    C1_REG_PIXEL_FORMAT    = 0x05cu,
    C1_REG_DESC_BASE_LO    = 0x080u,
    C1_REG_DESC_BASE_HI    = 0x084u,
    C1_REG_DESC_COUNT      = 0x088u,
    C1_REG_STYLE_ID        = 0x08cu,
    C1_REG_WEIGHT_BASE_LO  = 0x090u,
    C1_REG_WEIGHT_BASE_HI  = 0x094u,
    C1_REG_TENSOR_BASE     = 0x098u,
    C1_REG_DISPLAY_MODE    = 0x0c0u,
    C1_REG_FRAME_COUNT     = 0x100u,
    C1_REG_BUSY_CYCLES     = 0x104u,
    /* Aggregate shared-AXI QoS live read window (read-only, non-atomic). */
    C1_REG_QOS_STATUS      = 0x108u,
    C1_REG_QOS_FRAME_COUNT = 0x10cu,
    C1_REG_QOS_LAST_FRAME  = 0x110u,
    C1_REG_QOS_DEADLINE    = 0x114u,
    C1_REG_QOS_UNDERFLOW   = 0x118u,
    C1_REG_QOS_READ_BUSY   = 0x11cu,
    C1_REG_QOS_WRITE_BUSY  = 0x120u,
    C1_REG_QOS_R_OWNER_MAX = 0x124u,
    C1_REG_QOS_W_OWNER_MAX = 0x128u,
    C1_REG_QOS_PROTOCOL    = 0x12cu
};

enum {
    C1_QOS_STATUS_ENABLED  = 1u << 0,
    C1_QOS_STATUS_ACTIVE   = 1u << 1,
    C1_QOS_STATUS_OVERFLOW = 1u << 2,
    C1_QOS_STATUS_UNDERFLOW = 1u << 3,
    C1_QOS_STATUS_DEADLINE = 1u << 4,
    C1_QOS_STATUS_PROTOCOL = 1u << 5
};

enum {
    C1_REQUIRED_FRAME_WIDTH = 640u,
    C1_REQUIRED_FRAME_HEIGHT = 480u,
    C1_REQUIRED_DESCRIPTOR_COUNT = 22u,
    C1_DESCRIPTOR_BYTES = 64u,
    C1_PARAMETER_ARENA_BYTES = 16896u,
    C1_INPUT_TABLE_BYTES = 3u * 16u,
    C1_OUTPUT_TABLE_BYTES = 2u * 16u,
    C1_TENSOR_BANK_BYTES = 8u * 1024u * 1024u,
    C1_TENSOR_BANK_COUNT = 3u,
    C1_TENSOR_ARENA_BYTES = C1_TENSOR_BANK_BYTES * C1_TENSOR_BANK_COUNT,
    C1_TENSOR_ARENA_ALIGNMENT = C1_TENSOR_BANK_BYTES
};

enum {
    C1_CONTROL_ENABLE       = 1u << 0,
    C1_CONTROL_START        = 1u << 1,
    C1_CONTROL_ABORT        = 1u << 2,
    C1_CONTROL_CONTINUOUS   = 1u << 3,
    C1_CONTROL_DROP_OLDEST  = 1u << 4,
    C1_CONTROL_CLEAR_STATS  = 1u << 5
};

enum {
    C1_STATUS_IDLE = 1u << 0,
    C1_STATUS_BUSY = 1u << 1,
    C1_STATUS_DONE = 1u << 2,
    C1_STATUS_ERROR = 1u << 3
};

enum {
    C1_IRQ_DONE = 1u << 0,
    C1_IRQ_ERROR = 1u << 1,
    C1_IRQ_CAPTURE_DROP = 1u << 2,
    C1_IRQ_DISPLAY_SWAP = 1u << 3,
    C1_IRQ_DISPLAY_UNDERFLOW = 1u << 4,
    C1_IRQ_ALL = 0x1fu
};

enum {
    C1_PIXEL_RGB888_STREAM = 1u,
    C1_PIXEL_XRGB8888_DDR = 2u,
    C1_DISPLAY_STYLED = 0u,
    C1_DISPLAY_ORIGINAL = 1u,
    C1_DISPLAY_SPLIT = 2u,
    C1_DISPLAY_FAIL_BLACK = 3u,
    C1_DISPLAY_OSD_ENABLE = 0x80u
};

typedef struct {
    uint64_t input_buffer_table;
    uint64_t output_buffer_table;
    uint64_t descriptor_base;
    uint64_t weight_base;
    uint64_t tensor_base;
    uint32_t input_stride_bytes;
    uint32_t output_stride_bytes;
    uint16_t width;
    uint16_t height;
    uint16_t descriptor_count;
    uint8_t input_format;
    uint8_t output_format;
    uint8_t style_id;
    uint8_t display_mode;
    bool continuous;
    bool drop_oldest;
} c1_accel_config_t;

typedef struct {
    uintptr_t base;
    uint32_t steady_control;
} c1_accel_t;

typedef struct {
    uint32_t status;
    uint32_t frame_count;
    uint32_t last_frame_cycles;
    uint32_t deadline_miss_count;
    uint32_t underflow_count;
    uint32_t read_busy_cycles;
    uint32_t write_busy_cycles;
    uint32_t read_owner_hold_max;
    uint32_t write_owner_hold_max;
    uint32_t protocol_error_count;
} c1_accel_qos_snapshot_t;

bool c1_accel_probe(const c1_accel_t *device);
bool c1_accel_configure(c1_accel_t *device, const c1_accel_config_t *config);
bool c1_accel_start(c1_accel_t *device);
bool c1_accel_wait_idle(const c1_accel_t *device, uint32_t poll_limit);
void c1_accel_abort(c1_accel_t *device);
void c1_accel_enable_irqs(const c1_accel_t *device, uint32_t mask);
uint32_t c1_accel_irq_status(const c1_accel_t *device);
void c1_accel_ack_irqs(const c1_accel_t *device, uint32_t mask);
uint32_t c1_accel_status(const c1_accel_t *device);
uint32_t c1_accel_frame_count(const c1_accel_t *device);
uint32_t c1_accel_busy_cycles(const c1_accel_t *device);
bool c1_accel_read_qos(const c1_accel_t *device,
                       c1_accel_qos_snapshot_t *snapshot);
uint8_t c1_accel_error_code(const c1_accel_t *device);
uint32_t c1_accel_error_address(const c1_accel_t *device);

#endif
