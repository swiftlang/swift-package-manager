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

#include <CCryptoBoringSSL_asn1.h>
#include <CCryptoBoringSSL_obj.h>
#include "CPackageCollectionSigning_ocsp.h"
#include "CPackageCollectionSigning_ocsp_local.h"
#include "CPackageCollectionSigning_obj_mac.h"

/*
 * Utility functions related to sending OCSP requests and extracting relevant
 * information from the response.
 */

/*
 * Add an OCSP_CERTID to an OCSP request. Return new OCSP_ONEREQ pointer:
 * useful if we want to add extensions.
 */

OCSP_ONEREQ *OCSP_request_add0_id(OCSP_REQUEST *req, OCSP_CERTID *cid)
{
    OCSP_ONEREQ *one = NULL;

    if ((one = OCSP_ONEREQ_new()) == NULL)
        return NULL;
    OCSP_CERTID_free(one->reqCert);
    one->reqCert = cid;
    if (req && !sk_OCSP_ONEREQ_push(req->tbsRequest->requestList, one)) {
        one->reqCert = NULL; /* do not free on error */
        goto err;
    }
    return one;
 err:
    OCSP_ONEREQ_free(one);
    return NULL;
}

/* Get response status */

int OCSP_response_status(OCSP_RESPONSE *resp)
{
    return (int)ASN1_ENUMERATED_get(resp->responseStatus);
}

/*
 * Extract basic response from OCSP_RESPONSE or NULL if no basic response
 * present.
 */

OCSP_BASICRESP *OCSP_response_get1_basic(OCSP_RESPONSE *resp)
{
    OCSP_RESPBYTES *rb;
    rb = resp->responseBytes;
    if (!rb) {
        return NULL;
    }
    if (OBJ_obj2nid(rb->responseType) != NID_id_pkix_OCSP_basic) {
        return NULL;
    }

    return ASN1_item_unpack(rb->response, ASN1_ITEM_rptr(OCSP_BASICRESP));
}
