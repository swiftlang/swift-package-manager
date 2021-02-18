/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

#if canImport(Security)
let isSupportedPlatform = true
#else
let isSupportedPlatform = false
#endif

let ecPrivateKey = """
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIMFnwA1gjIFnFZim4B2QvoXJIG2L4B8nH1BBZFlotA24oAoGCCqGSM49
AwEHoUQDQgAEkc2FgXZVz9llhV6+jAGPVHEcxBxK5tui9HWzvtE+ogKPr7i3e2JO
Xwm91hecppS11y/S8bLmrFxA+dCP/V7bnw==
-----END EC PRIVATE KEY-----
"""

let ecPublicKey = """
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEkc2FgXZVz9llhV6+jAGPVHEcxBxK
5tui9HWzvtE+ogKPr7i3e2JOXwm91hecppS11y/S8bLmrFxA+dCP/V7bnw==
-----END PUBLIC KEY-----
"""

let rsaPrivateKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEAoQIWz/MQ+mRShQxxxs+zlCLHRz+R1zUPKZhg3eggbXartfyI
OSPEDaVANCjE1QLg0dtGCpkbMAVQLkC7os5ZuW6A6qtSAU6WUBOvnDBPVumqmDUq
AeXGEQyDZqReRm3D4Ov4qOTlIk34pRhoCymaNTiw7GfyzzWOcPxcRGGTz6fv1gmS
wDnURBeL9QUAb2/sdAAsY/SZzziNF+womF8y3mn+IvlKL3EhtSxUfdZpPdFmxPza
oVIlllFQcKnxH4/0PZeyPK0Npq4kCqATXcYXmaa3Ms9tPcsQUggtAR/QepyrKmB1
SRAouHqKi+bGTlCpFSFbDgW422gfqXEEboh39QIDAQABAoIBAQCRUR9hxFHYjF9m
MhsmgyPjWZhel+N7RypOMneLEQzjfy3vbONOHxe98R4HdZxhXN2oyq1mt1UwfDsn
48j2YiPdFv1H0CSNhW5pC7t9zqRtHyyXf7RQTh/8Fz0pkMR98GfQQ2oElcKwuYrn
ByYwnPXPf0E/vXoKxp2vIDXuidssmUl37mvbyppGaVl+Is6GmAiZkNOKN8ZEXPvz
4BivJ3yhs/RiM5RUF93qj8j/3P6R8rXLemAE9jrKjGG7Vv966p1Fh9+wNnnnbT8t
zLDUVwD7Q/JERr+3Wdecp+pZIfWTvJJhE8R3IM4WrLQNeUEKo7YovfYA7rah3gP/
ixM2BM5pAoGBAM5+c7Sxl7hzII2yPxN2fIslyKw3E8HP1nnqUPUegFsU3TZRQUnZ
gm5JgQRPqFYy6fwouL07KdSb/zIes3ra/qkhaOewHsAvvvxKKM6FGqYrkb5BKv0s
gF/m4qg6GLSW3BVb/QfnwHdWE7z7KPGuomzg+pqshxTyKYkGN2l8IIu7AoGBAMeb
81636nRy62CYQhNCp13wqmmUJ8/VnNj2jdwdXQ5vlgQdrwFm2p52cEFn/AhL5WIn
GShRLKL/keK71tsD0hCsTuZISR1xFiFk0TFmjxSX+z2D9VGvSECtNfySRuroKorS
xIXsrx6dvk/Ef54yDus1O5vvdT3l6vSDbVJESFgPAoGBAIAFJ8kT/YNOZRVUOATi
Ba7jGvmiH+6d41OscMq3QU62rbr6P2cAofusOH+qvyvJ3wUFXht7raBxopK5M/7r
/MxwuTBDIZ13PIn/lDMNlIsHIhF5J6TUzTYn18gCVMTJbuMTJ9mZ1dpmlFAqyqSj
53FnPhdc9VaIGDYqk3ojia33AoGAd52bzNH3vMq1BJCZYANcWm4DIPu4k9JViKrP
Pe2WuzThOBw1qGhjb/xXrspKfQpGLnhxmfhzAEaYvL+FtH9onbc0HMmKjwsakO5i
cfEcouGknCt8kfOxH5jstitONizkeYZuYDcChh1PU2vUcg9bY1XmH77yiiJClz4+
/8KNe78CgYEArTT+XVctYq5jaFCtGqq3DD/DrgJeWS6V5Op0QgVrVKFeCH2mImOg
6+95qwqyl3xCTJNvLwcNB+yricsWfUicEPKfDJX1w8m5/fANMRZYXr2nmAZvS9Kw
pkG0a65+K/m4wnZIszEuNZ2ybjrHEwYdWygRkJUmHp5rzmjdKjCBkwU=
-----END RSA PRIVATE KEY-----
"""

let rsaPublicKey = """
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoQIWz/MQ+mRShQxxxs+z
lCLHRz+R1zUPKZhg3eggbXartfyIOSPEDaVANCjE1QLg0dtGCpkbMAVQLkC7os5Z
uW6A6qtSAU6WUBOvnDBPVumqmDUqAeXGEQyDZqReRm3D4Ov4qOTlIk34pRhoCyma
NTiw7GfyzzWOcPxcRGGTz6fv1gmSwDnURBeL9QUAb2/sdAAsY/SZzziNF+womF8y
3mn+IvlKL3EhtSxUfdZpPdFmxPzaoVIlllFQcKnxH4/0PZeyPK0Npq4kCqATXcYX
maa3Ms9tPcsQUggtAR/QepyrKmB1SRAouHqKi+bGTlCpFSFbDgW422gfqXEEboh3
9QIDAQAB
-----END PUBLIC KEY-----
"""

let certECPrivateKey = """
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIKRNt0dFe1qbIFqyWbpU3dvrdzRqZ18BrQBhIoSzm8K2oAoGCCqGSM49
AwEHoUQDQgAE7TEGQSoJ6YWtocE3GTe/GEXgLayMdIGDe1OL66KLECP1CKm0BsJy
Cz5Ae+Rox51jc8zTUcniBXZRNhoP6+6AhQ==
-----END EC PRIVATE KEY-----
"""

let certRSAPrivateKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAtFFRh3JRc3PEWmjJ6iygXdSyIeIrNYgVYQPU9t5QwrFQvWSE
IvLaxmKWY9cHOacYJaOgfK2LKuod72K0xFOKX00Ww9Pt6mileP9SKpCkwcT8WN4Z
BLH1dhUqWt32ZZnay0TDs9XT8JQM8vwZrQ2+TlOvVTJdmU8GQzeponj4iNRvoc6Q
g3CvBtADhJHfKW+TGFfDQf284NQEs/95DRual90yeu/E46uY18PGU2jlhJdyugAy
+dK+bBTvZrg0AGylGGZJEQeqPzmWkwMuRsyRTop606yd53op6MhJCEOrlE0aWvUs
Spd/OLPuh5+AhS0RLCkQ8wz/bYZbR66Z4pABewIDAQABAoIBAQCwJuzFrAkkB0kf
pVTzfqsfXwSyEzdw8UMpZkvq613sBLrCemqXlbXhrjgKyuqVCMaPJp1Gj2bwAoxB
6qR7Ur1PwohlwCihIZ/dZ1fGm01Iun5m9nlsW8lWlPCumj32HWpfvwqMKW0Fjixk
R6FxrIZoEFqtmSlU9p1AlyURwqnRSEsAHGeeIj4owD69p5fegjwOjVsJJdvnrU1Y
6iRH3ywlsasv8vonwWiqo2rY3z9SXXb4Omni6U39sKQfDH002wBtZNL9rt/Yx8CD
ua2iikH1BXOWKHl0Wu/swfkPqscX0nYPucMkcUCwZ+xAxZ8DIc1Y/yzgtNaiYEox
GsIMbzMpAoGBANmq1kMzf594jNmb8a23mB50viZYjgLQ8esBZVNHERRK8gAl4feH
uoNvkBdhmT3BtaQCl7RFP315I1LUGctjaWbs12xc2L+5t7kWVfAyHFo5n6eiXoQC
zIretNBzmILp1IJ76atKyhWuH0YWh+UWL6S8rr9K0m6ZWUqSOrvTioPPAoGBANQS
omXglhKBtZGRXiaZpZt2Qz/nPNY95NLEK3yN6lwvI192KEjEkulqJyFELmFoeK4P
uAq5yuXp6qB7BlqxZYGj6/qnsTomeJZb0dwimISHXM46WoSq5sJ0srn8ln/N30PK
8NysaCLaIz13Jonll5D2kCvvZ4Ia8WJq+LkaapaVAoGAZC/K4TGR+3/MLNknW1MW
9GW9o/68lrU/tHB3B+a9CL8aNlE5eeqCQb8W7nwgwZkolu4Oj44UFBeu15ACs2f1
esdmvFzb8xtzYgDS23TlMe41+z20DUUQipbJWOzr9M3V351TR2FsNKBpiqQSNrKI
iWXDdQ7mXru8qqM134AV0GcCgYAKLiLRlShfFw7qP/ovDC0g+1pbFPScrDfxzizw
O7fGWRTvnjJs29LZlZjvReCcGHHCmUqSaTzOMJ5subsiW2WuBXpse+RMEFC1lw7J
7Hc51W2lELQLrlCJgSSbPP7Uf8N586IAVd5h3erXJoMZF4ZhFRTypvlnC3gO62ep
KxV2yQKBgF5nM2fs31xPsHN3Q/iGiQQQG//PIUttCl47XcUnxoabgebIq+lp5UmQ
ArYcBO4+cBZSbNjmUdUOSyM8fAUrWmy4QyvZXNy15V7W6qVzxfa0hT8T6tFUVmKG
qseI/cG+CoygHw9OqBcffl1d8LVAHmF8mkfzJ2CnQs9CLFxS1+f9
-----END RSA PRIVATE KEY-----
"""

extension String {
    var bytes: [UInt8] {
        [UInt8](self.utf8)
    }
}
