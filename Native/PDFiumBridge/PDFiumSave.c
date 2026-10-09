#include "BotPlusPDFium.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    FPDF_FILEWRITE interface;
    unsigned char* bytes;
    size_t length;
    size_t capacity;
} BotPlusWriter;

static int BotPlusWriteBlock(FPDF_FILEWRITE* interface, const void* data, unsigned long size) {
    BotPlusWriter* writer = (BotPlusWriter*)interface;
    if (size > SIZE_MAX - writer->length) return 0;
    size_t required = writer->length + (size_t)size;
    if (required > writer->capacity) {
        size_t capacity = writer->capacity ? writer->capacity : 65536;
        while (capacity < required) {
            if (capacity > SIZE_MAX / 2) { capacity = required; break; }
            capacity *= 2;
        }
        unsigned char* resized = (unsigned char*)realloc(writer->bytes, capacity);
        if (!resized) return 0;
        writer->bytes = resized;
        writer->capacity = capacity;
    }
    if (size) memcpy(writer->bytes + writer->length, data, (size_t)size);
    writer->length = required;
    return 1;
}

unsigned char* BotPlusPDFium_SaveDocument(FPDF_DOCUMENT document, size_t* length) {
    if (!document || !length) return NULL;
    *length = 0;
    BotPlusWriter writer = {{1, BotPlusWriteBlock}, NULL, 0, 0};
    if (!FPDF_SaveAsCopy(document, &writer.interface, FPDF_NO_INCREMENTAL)) {
        free(writer.bytes);
        return NULL;
    }
    *length = writer.length;
    return writer.bytes;
}
void BotPlusPDFium_Free(void* memory) { free(memory); }
