// A relative path to SharedTypes.h.
#import "../MySharedTypes/include/SharedTypes.h"

#include <metal_stdlib>
using namespace metal;

vertex float4 simpleVertexShader(const device AAPLVertex *vertices [[buffer(0)]],
                                  uint vertexID [[vertex_id]]) {
    AAPLVertex in = vertices[vertexID];
    return float4(in.position.x, in.position.y, 0.0, 1.0);
}

