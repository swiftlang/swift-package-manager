//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/*
 * Copyright 1995-2020 The OpenSSL Project Authors. All Rights Reserved.
 *
 * Licensed under the Apache License 2.0 (the "License").  You may not use
 * this file except in compliance with the License.  You can obtain a copy
 * in the file LICENSE in the source distribution or at
 * https://www.openssl.org/source/license.html
 */

/* Copyright (C) 1995-1998 Eric Young (eay@cryptsoft.com)
 * All rights reserved.
 *
 * This package is an SSL implementation written
 * by Eric Young (eay@cryptsoft.com).
 * The implementation was written so as to conform with Netscapes SSL.
 *
 * This library is free for commercial and non-commercial use as long as
 * the following conditions are aheared to.  The following conditions
 * apply to all code found in this distribution, be it the RC4, RSA,
 * lhash, DES, etc., code; not just the SSL code.  The SSL documentation
 * included with this distribution is covered by the same copyright terms
 * except that the holder is Tim Hudson (tjh@cryptsoft.com).
 *
 * Copyright remains Eric Young's, and as such any Copyright notices in
 * the code are not to be removed.
 * If this package is used in a product, Eric Young should be given attribution
 * as the author of the parts of the library used.
 * This can be in the form of a textual message at program startup or
 * in documentation (online or textual) provided with the package.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *    "This product includes cryptographic software written by
 *     Eric Young (eay@cryptsoft.com)"
 *    The word 'cryptographic' can be left out if the rouines from the library
 *    being used are not cryptographic related :-).
 * 4. If you include any Windows specific code (or a derivative thereof) from
 *    the apps directory (application code) you must include an acknowledgement:
 *    "This product includes software written by Tim Hudson (tjh@cryptsoft.com)"
 *
 * THIS SOFTWARE IS PROVIDED BY ERIC YOUNG ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * The licence and distribution terms for any publically available version or
 * derivative of this code cannot be changed.  i.e. this code cannot simply be
 * copied and put under another distribution licence
 * [including the GNU Public Licence.] */

#include <limits.h>
#include <CCryptoBoringSSL_asn1.h>
#include <CCryptoBoringSSL_buffer.h>
#include <CCryptoBoringSSL_err.h>
#include "CPackageCollectionSigning_asn1.h"

static int asn1_d2i_read_bio(BIO *in, BUF_MEM **pb);
static int ASN1_get_object_without_inf(const unsigned char **pp, long *plength,
                                       int *ptag, int *pclass, long omax);
static int asn1_get_length_without_inf(const unsigned char **pp, long *rl, long max);
static int asn1_get_length_with_inf(const unsigned char **pp, int *inf,
                                    long *rl, long max);
static int ASN1_get_object_with_inf(const unsigned char **pp, long *plength,
                                    int *ptag, int *pclass, long omax);

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
    int ret, tag, xclass;

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
        ret = ASN1_get_object_without_inf(&q, &slen, &tag, &xclass, len - off);
        if (ret & 0x80) {
            unsigned long e;

            e = ERR_GET_REASON(ERR_peek_error());
            if (e != ASN1_R_TOO_LONG)
                goto err;
            else
                ERR_clear_error(); /* clear error */
        }
        i = (int)(q - p);            /* header length */
        off += i;               /* end of data */

        if (eos && (slen == 0) && (tag == V_ASN1_EOC)) {
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

// https://github.com/google/boringssl/blob/ee510f58895c6a88b59f1b66a94939d08ebdfe5b/crypto/asn1/asn1_lib.c
static int ASN1_get_object_without_inf(const unsigned char **pp, long *plength,
                                       int *ptag, int *pclass, long omax)
{
    int i, ret;
    long l;
    const unsigned char *p = *pp;
    int tag, xclass;
    long max = omax;

    if (!max)
        goto err;
    ret = (*p & V_ASN1_CONSTRUCTED);
    xclass = (*p & V_ASN1_PRIVATE);
    i = *p & V_ASN1_PRIMITIVE_TAG;
    if (i == V_ASN1_PRIMITIVE_TAG) { /* high-tag */
        p++;
        if (--max == 0)
            goto err;
        l = 0;
        while (*p & 0x80) {
            l <<= 7L;
            l |= *(p++) & 0x7f;
            if (--max == 0)
                goto err;
            if (l > (INT_MAX >> 7L))
                goto err;
        }
        l <<= 7L;
        l |= *(p++) & 0x7f;
        tag = (int)l;
        if (--max == 0)
            goto err;
    } else {
        tag = i;
        p++;
        if (--max == 0)
            goto err;
    }

    /* To avoid ambiguity with V_ASN1_NEG, impose a limit on universal tags. */
    if (xclass == V_ASN1_UNIVERSAL && tag > V_ASN1_MAX_UNIVERSAL)
        goto err;

    *ptag = tag;
    *pclass = xclass;
    if (!asn1_get_length_without_inf(&p, plength, max))
        goto err;

    if (*plength > (omax - (p - *pp))) {
        OPENSSL_PUT_ERROR(ASN1, ASN1_R_TOO_LONG);
        /*
         * Set this so that even if things are not long enough the values are
         * set correctly
         */
        ret |= 0x80;
    }
    *pp = p;
    return ret;
 err:
    OPENSSL_PUT_ERROR(ASN1, ASN1_R_HEADER_TOO_LONG);
    return 0x80;
}

static int asn1_get_length_without_inf(const unsigned char **pp, long *rl, long max)
{
    const unsigned char *p = *pp;
    unsigned long ret = 0;
    unsigned long i;

    if (max-- < 1) {
        return 0;
    }
    if (*p == 0x80) {
        /* We do not support BER indefinite-length encoding. */
        return 0;
    }
    i = *p & 0x7f;
    if (*(p++) & 0x80) {
        if (i > sizeof(ret) || max < (long)i)
            return 0;
        while (i-- > 0) {
            ret <<= 8L;
            ret |= *(p++);
        }
    } else {
        ret = i;
    }
    /*
     * Bound the length to comfortably fit in an int. Lengths in this module
     * often switch between int and long without overflow checks.
     */
    if (ret > INT_MAX / 2)
        return 0;
    *pp = p;
    *rl = (long)ret;
    return 1;
}

// https://github.com/google/boringssl/blob/a7e807481bfab5fcf72cd6b396f57cb2990bf63a/crypto/asn1/asn1_lib.c
static int ASN1_get_object_with_inf(const unsigned char **pp, long *plength,
                                    int *ptag, int *pclass, long omax)
{
    int i, ret;
    long l;
    const unsigned char *p = *pp;
    int tag, xclass, inf;
    long max = omax;

    if (!max)
        goto err;
    ret = (*p & V_ASN1_CONSTRUCTED);
    xclass = (*p & V_ASN1_PRIVATE);
    i = *p & V_ASN1_PRIMITIVE_TAG;
    if (i == V_ASN1_PRIMITIVE_TAG) { /* high-tag */
        p++;
        if (--max == 0)
            goto err;
        l = 0;
        while (*p & 0x80) {
            l <<= 7L;
            l |= *(p++) & 0x7f;
            if (--max == 0)
                goto err;
            if (l > (INT_MAX >> 7L))
                goto err;
        }
        l <<= 7L;
        l |= *(p++) & 0x7f;
        tag = (int)l;
        if (--max == 0)
            goto err;
    } else {
        tag = i;
        p++;
        if (--max == 0)
            goto err;
    }

    /* To avoid ambiguity with V_ASN1_NEG, impose a limit on universal tags. */
    if (xclass == V_ASN1_UNIVERSAL && tag > V_ASN1_MAX_UNIVERSAL)
        goto err;

    *ptag = tag;
    *pclass = xclass;
    if (!asn1_get_length_with_inf(&p, &inf, plength, max))
        goto err;

    if (inf && !(ret & V_ASN1_CONSTRUCTED))
        goto err;

    if (*plength > (omax - (p - *pp))) {
        OPENSSL_PUT_ERROR(ASN1, ASN1_R_TOO_LONG);
        /*
         * Set this so that even if things are not long enough the values are
         * set correctly
         */
        ret |= 0x80;
    }
    *pp = p;
    return (ret | inf);
 err:
    OPENSSL_PUT_ERROR(ASN1, ASN1_R_HEADER_TOO_LONG);
    return 0x80;
}

static int asn1_get_length_with_inf(const unsigned char **pp, int *inf,
                                    long *rl, long max)
{
    const unsigned char *p = *pp;
    unsigned long ret = 0;
    unsigned long i;

    if (max-- < 1)
        return 0;
    if (*p == 0x80) {
        *inf = 1;
        ret = 0;
        p++;
    } else {
        *inf = 0;
        i = *p & 0x7f;
        if (*(p++) & 0x80) {
            if (i > sizeof(ret) || max < (long)i)
                return 0;
            while (i-- > 0) {
                ret <<= 8L;
                ret |= *(p++);
            }
        } else
            ret = i;
    }
    /*
     * Bound the length to comfortably fit in an int. Lengths in this module
     * often switch between int and long without overflow checks.
     */
    if (ret > INT_MAX / 2)
        return 0;
    *pp = p;
    *rl = (long)ret;
    return 1;
}
