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

#ifndef C_PACKAGE_COLLECTION_SIGNING_OCSP_H
#define C_PACKAGE_COLLECTION_SIGNING_OCSP_H

#include <CCryptoBoringSSL_stack.h>
#include <CCryptoBoringSSL_base.h>
#include <CCryptoBoringSSL_x509.h>

#if defined(__cplusplus)
extern "C" {
#endif

typedef struct ocsp_cert_id_st OCSP_CERTID;

DEFINE_STACK_OF(OCSP_CERTID)

typedef struct ocsp_one_request_st OCSP_ONEREQ;

DEFINE_STACK_OF(OCSP_ONEREQ)

typedef struct ocsp_req_info_st OCSP_REQINFO;
typedef struct ocsp_signature_st OCSP_SIGNATURE;
typedef struct ocsp_request_st OCSP_REQUEST;

typedef struct ocsp_resp_bytes_st OCSP_RESPBYTES;

#define OCSP_RESPONSE_STATUS_SUCCESSFUL           0
#define OCSP_RESPONSE_STATUS_MALFORMEDREQUEST     1
#define OCSP_RESPONSE_STATUS_INTERNALERROR        2
#define OCSP_RESPONSE_STATUS_TRYLATER             3
#define OCSP_RESPONSE_STATUS_SIGREQUIRED          5
#define OCSP_RESPONSE_STATUS_UNAUTHORIZED         6

typedef struct ocsp_response_st OCSP_RESPONSE;

#define V_OCSP_RESPID_NAME 0
#define V_OCSP_RESPID_KEY  1

typedef struct ocsp_responder_id_st OCSP_RESPID;

DEFINE_STACK_OF(OCSP_RESPID)

typedef struct ocsp_revoked_info_st OCSP_REVOKEDINFO;

#define V_OCSP_CERTSTATUS_GOOD    0
#define V_OCSP_CERTSTATUS_REVOKED 1
#define V_OCSP_CERTSTATUS_UNKNOWN 2

typedef struct ocsp_cert_status_st OCSP_CERTSTATUS;
typedef struct ocsp_single_response_st OCSP_SINGLERESP;

DEFINE_STACK_OF(OCSP_SINGLERESP)

typedef struct ocsp_response_data_st OCSP_RESPDATA;

typedef struct ocsp_basic_response_st OCSP_BASICRESP;

OCSP_CERTID *OCSP_cert_to_id(const EVP_MD *dgst, const X509 *subject,
                             const X509 *issuer);

OCSP_CERTID *OCSP_cert_id_new(const EVP_MD *dgst,
                              const X509_NAME *issuerName,
                              const ASN1_BIT_STRING *issuerKey,
                              const ASN1_INTEGER *serialNumber);

OCSP_ONEREQ *OCSP_request_add0_id(OCSP_REQUEST *req, OCSP_CERTID *cid);

DECLARE_ASN1_FUNCTIONS(OCSP_CERTID)
DECLARE_ASN1_FUNCTIONS(OCSP_ONEREQ)
DECLARE_ASN1_FUNCTIONS(OCSP_REQINFO)
DECLARE_ASN1_FUNCTIONS(OCSP_SIGNATURE)
DECLARE_ASN1_FUNCTIONS(OCSP_REQUEST)
DECLARE_ASN1_FUNCTIONS(OCSP_RESPBYTES)
DECLARE_ASN1_FUNCTIONS(OCSP_RESPONSE)
DECLARE_ASN1_FUNCTIONS(OCSP_RESPID)
DECLARE_ASN1_FUNCTIONS(OCSP_REVOKEDINFO)
DECLARE_ASN1_FUNCTIONS(OCSP_CERTSTATUS)
DECLARE_ASN1_FUNCTIONS(OCSP_SINGLERESP)
DECLARE_ASN1_FUNCTIONS(OCSP_RESPDATA)
DECLARE_ASN1_FUNCTIONS(OCSP_BASICRESP)

int i2d_OCSP_REQUEST_bio(BIO *out, OCSP_REQUEST *req);
OCSP_RESPONSE *d2i_OCSP_RESPONSE_bio(BIO *in, OCSP_RESPONSE **res);

int OCSP_response_status(OCSP_RESPONSE *resp);
OCSP_BASICRESP *OCSP_response_get1_basic(OCSP_RESPONSE *resp);

#define OCSP_NOINTERN                   0x2
#define OCSP_NOSIGS                     0x4
#define OCSP_NOCHAIN                    0x8
#define OCSP_NOVERIFY                   0x10
#define OCSP_NOEXPLICIT                 0x20
#define OCSP_NOCHECKS                   0x100
#define OCSP_TRUSTOTHER                 0x200
#define OCSP_PARTIAL_CHAIN              0x1000

int OCSP_id_issuer_cmp(const OCSP_CERTID *a, const OCSP_CERTID *b);

#define OCSP_BASICRESP_verify(a,r) ASN1_item_verify(ASN1_ITEM_rptr(OCSP_RESPDATA),\
        (a)->signatureAlgorithm,(a)->signature,(a)->tbsResponseData,r)

int OCSP_basic_verify(OCSP_BASICRESP *bs, STACK_OF(X509) *certs,
                      X509_STORE *st, unsigned long flags);

#if defined(__cplusplus)
}  // extern C
#endif

#endif
