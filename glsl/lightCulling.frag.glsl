#version 100

// precision highp vec4;
precision highp float;
precision highp int;


#define USE_TILE_MIN_MAX_DEPTH_CULLING 0

#define TILE_SIZE 16

varying vec2 v_uv;

uniform mat4 u_viewMatrix;
uniform mat4 u_projectionMatrix;

uniform int u_numLights; 

// size of screen fb
uniform int u_textureWidth;
uniform int u_textureHeight;

uniform sampler2D u_lightPositionTexture;   //RGB
uniform sampler2D u_lightColorRadiusTexture;    //RGBA

uniform sampler2D u_tileLightsTexture;    // RGB, store light indices in a tile

uniform sampler2D u_depthTexture;



void main() {

    ivec2 pixelIdx = ivec2(gl_FragCoord.xy);    // floored
    ivec2 tileIdx = pixelIdx / TILE_SIZE;
    ivec2 tilePixel0Idx = tileIdx * TILE_SIZE;  // bottom-left pixelId of this tile

    ivec2 deltaIdx = pixelIdx - tilePixel0Idx;
    int lightIdx = deltaIdx.y * TILE_SIZE + deltaIdx.x;

    // TODO: unwrap the rgba (one pixel handle 4 lights) 


#if USE_TILE_MIN_MAX_DEPTH_CULLING
    // get min and max depth
    float farDepth = 999999.0;
    float nearDepth = -999999.0;
    for (int y = 0; y < TILE_SIZE; y++)
    {
        for (int x = 0; x < TILE_SIZE; x++)
        {
            ivec2 pid = tilePixel0Idx + ivec2(x, y);
            vec2 uv = (vec2(pid) + vec2(0.5, 0.5)) / vec2(u_textureWidth, u_textureHeight);

            float d = texture2D(u_depthTexture, uv).r;
            // transform depth value to view space
            
            d = 2.0 * d - 1.0;  //(0, 1) => (-1, 1)
            d = - u_projectionMatrix[3][2] / (d + u_projectionMatrix[2][2]);

            farDepth = min(d, farDepth);
            nearDepth = max(d, nearDepth);
        }
    }
#endif



    if (lightIdx < u_numLights)
    {
        vec2 lightUV = vec2( (float(lightIdx) + 0.5 ) / float(u_numLights) , 0.5); 

        vec4 lightPos = vec4(texture2D(u_lightPositionTexture, lightUV).xyz, 1.0);
        float lightRadius = texture2D(u_lightColorRadiusTexture, lightUV).w;

        // Test if light overlap with this tile (lightCulling)
        
        // calculate the frustum box in view space
        // credit: http://www.txutxi.com/?p=444

        mat4 M = u_projectionMatrix;
        
        vec2 fullScreenSize = vec2(u_textureWidth, u_textureHeight);

        // tile position in NDC space
        vec2 floorCoord = 2.0 * vec2(tilePixel0Idx) / fullScreenSize - vec2(1.0);  // -1, 1
        vec2 ceilCoord = 2.0 * vec2(tilePixel0Idx + ivec2(TILE_SIZE)) / fullScreenSize - vec2(1.0);  // -1, 1

        float viewNear = - M[3][2] / ( -1.0 + M[2][2]);
        float viewFar = - M[3][2] / (1.0 + M[2][2]);
        // float viewNear = -1.0;
        // float viewFar = -1000.0;
        vec2 viewFloorCoord = vec2( (- viewNear * floorCoord.x - M[2][0] * viewNear) / M[0][0] , (- viewNear * floorCoord.y - M[2][1] * viewNear) / M[1][1] );
        vec2 viewCeilCoord = vec2( (- viewNear * ceilCoord.x - M[2][0] * viewNear) / M[0][0] , (- viewNear * ceilCoord.y - M[2][1] * viewNear) / M[1][1] );



        // calculate frustumPlanes for each tile in view space

#if USE_TILE_MIN_MAX_DEPTH_CULLING
        vec4 frustumPlanes[6];
#else
        vec4 frustumPlanes[4];
#endif

        frustumPlanes[0] = vec4(1.0, 0.0, - viewFloorCoord.x / viewNear, 0.0);       // left
        frustumPlanes[1] = vec4(-1.0, 0.0, viewCeilCoord.x / viewNear, 0.0);   // right
        frustumPlanes[2] = vec4(0.0, 1.0, - viewFloorCoord.y / viewNear, 0.0);       // bottom
        frustumPlanes[3] = vec4(0.0, -1.0, viewCeilCoord.y / viewNear, 0.0);   // top

#if USE_TILE_MIN_MAX_DEPTH_CULLING
        frustumPlanes[4] = vec4(0.0, 0.0, -1.0, nearDepth);    // near
        frustumPlanes[5] = vec4(0.0, 0.0, 1.0, -farDepth);    // far
#endif

        // transform lightPos to view space
        lightPos = u_viewMatrix * lightPos;
        lightPos /= lightPos.w;
        
        vec4 boxMin = lightPos - vec4( vec3(lightRadius), 0.0);
        vec4 boxMax = lightPos + vec4( vec3(lightRadius), 0.0);


        float dp = 0.0;     //dot product

#if USE_TILE_MIN_MAX_DEPTH_CULLING
        for (int i = 0; i < 6; i++)
#else
        dp += lightPos.z > viewNear + lightRadius ? -1.0 : 0.0;
        dp += lightPos.z < viewFar - lightRadius ? -1.0 : 0.0;

        for (int i = 0; i < 4; i++)
#endif
        {
            dp += min(0.0, dot(
                vec4( 
                    frustumPlanes[i].x > 0.0 ? boxMax.x : boxMin.x, 
                    frustumPlanes[i].y > 0.0 ? boxMax.y : boxMin.y, 
                    frustumPlanes[i].z > 0.0 ? boxMax.z : boxMin.z, 
                    1.0), 
                frustumPlanes[i]));
        }

        


        if (dp < 0.0) 
        {
            // exists some of the plane fails the test
            // no overlapping

            gl_FragColor = vec4(0.0, 0.0, 0.5, 1.0);
            // gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
        }
        else
        {
            // overlapping
            gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
        }



        // ------------ debug output ------------------
        // gl_FragColor = vec4(frustumPlanes[0].x / 10.0, 0.0, 0.0, 1.0);
        // gl_FragColor = vec4(viewFloorCoord*2.0 - 0.1, 0.0, 1.0);
        // gl_FragColor = vec4(vec3(-viewNear * 0.5), 1.0);
        // gl_FragColor = vec4(vec3(-viewFar / 2000.0), 1.0);
        // gl_FragColor = vec4(vec3(-nearDepth)/20.0, 1.0);
        // gl_FragColor = vec4( 0.5 * (lightPos.xy + 1.0), 0.0, 1.0);
        // gl_FragColor = vec4(vec2(tilePixel0Idx) / fullScreenSize, 0.0 , 1.0);
        // gl_FragColor = vec4(vec3(1.0 - lightRadius), 1.0);
        // gl_FragColor = vec4(vec3(lightRadius), 1.0);
        // gl_FragColor = vec4(vec3(radiusHorizontalNDC), 1.0);

        // gl_FragColor = vec4(vec3(1.0 - 0.0), 1.0);
        // gl_FragColor = vec4(floorCoord.xy, 0.0, 1.0);
        // gl_FragColor = vec4(ceilCoord.xy, 0.0, 1.0);
        // gl_FragColor = vec4(radiusHorizontalNDC, radiusVerticalNDC, 0.0, 1.0);
        


        // uv that we are going to write 1/0 for u_tileLightsTexture
        // vec2 uv = (vec2(pixelIdx) + vec2(0.5, 0.5)) / vec2(u_textureWidth, u_textureHeight);
        

        // // Debug output: lightPos
        // gl_FragColor = vec4(0.0, lightPos.y / 18.0, 0.0, 1.0);
    }
    else
    {
        gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    }

}