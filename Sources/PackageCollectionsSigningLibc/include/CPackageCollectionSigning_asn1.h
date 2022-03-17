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

#ifndef C_PACKAGE_COLLECTION_SIGNING_ASN1_H
#define C_PACKAGE_COLLECTION_SIGNING_ASN1_H

#include <CCryptoBoringSSL_asn1.h>

#if defined(__cplusplus)
extern "C" {
#endif

#define D2I_OF(type) type *(*)(type **,const unsigned char **,long)
#define I2D_OF(type) int (*)(type *,unsigned char **)

#define CHECKED_D2I_OF(type, d2i) \
    ((d2i_of_void*) (1 ? d2i : ((D2I_OF(type))0)))
#define CHECKED_I2D_OF(type, i2d) \
    ((i2d_of_void*) (1 ? i2d : ((I2D_OF(type))0)))
#define CHECKED_NEW_OF(type, xnew) \
    ((void *(*)(void)) (1 ? xnew : ((type *(*)(void))0)))
#define CHECKED_PTR_OF(type, p) \
    ((void*) (1 ? p : (type*)0))
#define CHECKED_PPTR_OF(type, p) \
    ((void**) (1 ? p : (type**)0))

void *ASN1_d2i_bio(void *(*xnew) (void), d2i_of_void *d2i, BIO *in, void **x);

#define ASN1_d2i_bio_of(type,xnew,d2i,in,x) \
    ((type*)ASN1_d2i_bio(CHECKED_NEW_OF(type, xnew), \
                         CHECKED_D2I_OF(type, d2i), \
                         in, \
                         CHECKED_PPTR_OF(type, x)))

int ASN1_i2d_bio(i2d_of_void *i2d, BIO *out, unsigned char *x);

#define ASN1_i2d_bio_of(type,i2d,out,x) \
    (ASN1_i2d_bio(CHECKED_I2D_OF(type, i2d), \
                  out, \
                  CHECKED_PTR_OF(type, x)))

#if defined(__cplusplus)
}  // extern C
#endif

#endif
