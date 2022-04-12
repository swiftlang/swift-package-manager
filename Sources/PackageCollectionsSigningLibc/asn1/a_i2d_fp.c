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

#include <CCryptoBoringSSL_mem.h>
#include "CPackageCollectionSigning_asn1.h"

int ASN1_i2d_bio(i2d_of_void *i2d, BIO *out, unsigned char *x)
{
    char *b;
    unsigned char *p;
    int i, j = 0, n, ret = 1;
    
    n = i2d(x, NULL);
    if (n <= 0)
        return 0;

    b = OPENSSL_malloc(n);
    if (b == NULL) {
        return 0;
    }

    p = (unsigned char *)b;
    i2d(x, &p);

    for (;;) {
        i = BIO_write(out, &(b[j]), n);
        if (i == n)
            break;
        if (i <= 0) {
            ret = 0;
            break;
        }
        j += i;
        n -= i;
    }
    OPENSSL_free(b);
    return ret;
}
