/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/*
 * Copyright 1995-2020 The OpenSSL Project Authors. All Rights Reserved.
 *
 * Licensed under the Apache License 2.0 (the "License").  You may not use
 * this file except in compliance with the License.  You can obtain a copy
 * in the file LICENSE in the source distribution or at
 * https://www.openssl.org/source/license.html
 */

#include <limits.h>
#include <CCryptoBoringSSL_asn1.h>
#include <CCryptoBoringSSL_buffer.h>
#include <CCryptoBoringSSL_err.h>
#include "CPackageCollectionSigning_asn1.h"

static int asn1_d2i_read_bio(BIO *in, BUF_MEM **pb);

void *ASN1_d2i_bio(void *(*xnew) (void), d2i_of_void *d2i, BIO *in, void **x)
{
    BUF_MEM *b = NULL;
    const unsigned char *p;
    void *ret = NULL;
    int len;

    len = asn1_d2i_read_bio(in, &b);
    if (len < 0)
        goto err;

    p = (unsigned char *)b->data;
    ret = d2i(x, &p, len);
 err:
    BUF_MEM_free(b);
    return ret;
}

#define HEADER_SIZE   8
#define ASN1_CHUNK_INITIAL_SIZE (16 * 1024)
static int asn1_d2i_read_bio(BIO *in, BUF_MEM **pb)
{
    BUF_MEM *b;
    unsigned char *p;
    int i;
    size_t want = HEADER_SIZE;
    uint32_t eos = 0;
    size_t off = 0;
    size_t len = 0;

    const unsigned char *q;
    long slen;
    int inf, tag, xclass;

    b = BUF_MEM_new();
    if (b == NULL) {
        return -1;
    }

    ERR_clear_error();
    for (;;) {
        if (want >= (len - off)) {
            want -= (len - off);

            if (len + want < len || !BUF_MEM_grow_clean(b, len + want)) {
                goto err;
            }
            i = BIO_read(in, &(b->data[len]), (int)want);
            if ((i < 0) && ((len - off) == 0)) {
                goto err;
            }
            if (i > 0) {
                if (len + i < len) {
                    goto err;
                }
                len += i;
            }
        }
        /* else data already loaded */

        p = (unsigned char *)&(b->data[off]);
        q = p;
        inf = ASN1_get_object(&q, &slen, &tag, &xclass, len - off);
        if (inf & 0x80) {
            unsigned long e;

            e = ERR_GET_REASON(ERR_peek_error());
            if (e != ASN1_R_TOO_LONG)
                goto err;
            else
                ERR_clear_error(); /* clear error */
        }
        i = (int)(q - p);            /* header length */
        off += i;               /* end of data */

        if (inf & 1) {
            /* no data body so go round again */
            if (eos == UINT32_MAX) {
                goto err;
            }
            eos++;
            want = HEADER_SIZE;
        } else if (eos && (slen == 0) && (tag == V_ASN1_EOC)) {
            /* eos value, so go back and read another header */
            eos--;
            if (eos == 0)
                break;
            else
                want = HEADER_SIZE;
        } else {
            /* suck in slen bytes of data */
            want = slen;
            if (want > (len - off)) {
                size_t chunk_max = ASN1_CHUNK_INITIAL_SIZE;

                want -= (len - off);
                if (want > INT_MAX /* BIO_read takes an int length */  ||
                    len + want < len) {
                    goto err;
                }
                while (want > 0) {
                    /*
                     * Read content in chunks of increasing size
                     * so we can return an error for EOF without
                     * having to allocate the entire content length
                     * in one go.
                     */
                    size_t chunk = want > chunk_max ? chunk_max : want;

                    if (!BUF_MEM_grow_clean(b, len + chunk)) {
                        goto err;
                    }
                    want -= chunk;
                    while (chunk > 0) {
                        i = BIO_read(in, &(b->data[len]), (int)chunk);
                        if (i <= 0) {
                            goto err;
                        }
                    /*
                     * This can't overflow because |len+want| didn't
                     * overflow.
                     */
                        len += i;
                        chunk -= i;
                    }
                    if (chunk_max < INT_MAX/2)
                        chunk_max *= 2;
                }
            }
            if (off + slen < off) {
                goto err;
            }
            off += slen;
            if (eos == 0) {
                break;
            } else
                want = HEADER_SIZE;
        }
    }

    if (off > INT_MAX) {
        goto err;
    }

    *pb = b;
    return (int)off;
 err:
    BUF_MEM_free(b);
    return -1;
}
