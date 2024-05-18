-- Put this in your lua folder --
if !EGSM or !(EGSM.Version > 1) then return end -- DON'T FORGET TO CHECK
-- Written By Ethan, TheGreat for public use/knowledge --
-- Originally created by Valve Corperation
-- & Facepunch Studios. 
-- Credits also belongs to EGSM (Required to use, see ReadME) as a whole entity. High quality work. 100%.
-- 
/*-- Vertex Shader, called per vertex. --*/
shaderlib.CompileVertexShader("VertexLitParallax_VertexShader", 0, [==[
    #include "common_vs_fxc.h"
    #include "shader_constant_register_map.h"
    
    struct VS_INPUT
    {
        float4 vPos                                 : POSITION;        // Position
        float4 vNormal                              : NORMAL;        // Normal
        float4 vBoneWeights                         : BLENDWEIGHT;    // Skin weights
        float4 vBoneIndices                         : BLENDINDICES;    // Skin indices
        float2 vTexCoord                            : TEXCOORD0;
    
        float4 vTangentS                            : TANGENT;
        float3 vTangentT                            : BINORMAL;
        float4 vColor                               : COLOR0;
        
    };

    struct VS_OUTPUT
    {
        float4 projPosSetup                         : POSITION;
        float2 vTexCoord                            : TEXCOORD0;

        float3 tEyePos                              : TEXCOORD1;
        float3 tLightPos                            : TEXCOORD2;
        float3 tFragPos                             : TEXCOORD3;

        float3 wNormal                              : TEXCOORD4;
    };

    VS_OUTPUT main( const VS_INPUT v )
    {
        VS_OUTPUT o = (VS_OUTPUT)0;

        float3 vObjNormal;
        float4 vObjTangent;
        float3 worldNormal;
		float3 worldPos;
		float3 worldTangentS;
		float3 worldTangentT;

        DecompressVertex_NormalTangent( v.vNormal, v.vTangentS, vObjNormal, vObjTangent );
		
        SkinPositionNormalAndTangentSpace( SKINNING, v.vPos, vObjNormal, vObjTangent, v.vBoneWeights, v.vBoneIndices, worldPos, worldNormal, worldTangentS, worldTangentT );
		
        float4 worldPosf = float4( worldPos, 1 );
        float4 vProjPos = mul( worldPosf, cViewProj );
            vProjPos.z = dot( worldPosf, cViewProjZ );
    
        float3x3 TBN = float3x3( 
            normalize(float3(worldTangentS.x, worldTangentT.x, worldNormal.x)),
            normalize(float3(worldTangentS.y, worldTangentT.y, worldNormal.y)),
            normalize(float3(worldTangentS.z, worldTangentT.z, worldNormal.z))
        );
        
        o.tEyePos =   (mul(TBN, cEyePos));
        o.tLightPos = (mul(TBN, float3(0.5f, 1.0f, 0.3f)));
        o.tFragPos = mul(TBN, worldPos);
        o.wNormal = worldNormal;
        o.projPosSetup = vProjPos;
        o.vTexCoord = float2( v.vTexCoord.x, v.vTexCoord.y );
        
        return o;
    }
]==])

/*-- Fragment Shader, called per PIXEL, per face. --*/
shaderlib.CompilePixelShader("VertexLitParallax_PixelShader", 0, [==[
	sampler tBaseMap : register(s0);
    sampler tNormalBuffer                           : register(s1);
    
    float curTime : register(c0);

    struct PS_IN
    {
        float2 pPos                                 : VPOS;
        float2 vTexCoord                            : TEXCOORD0;

        float3 tEyePos                              : TEXCOORD1;
        float3 tLightPos                            : TEXCOORD2;
        float3 tFragPos                             : TEXCOORD3;

        float4 wNormal: TEXCOORD4;
    };

    
    float2 ParallaxMapping(float2 texCoords, float3 viewDir, float3 wNormal)
    {
        float nMinLayers = 8.0;
        float nMaxLayers = 150.0;
        float numLayers = lerp(nMaxLayers, nMinLayers, max(dot(viewDir, wNormal), 0 ));
        float layerDepth = 1.0 / numLayers;

        float currentLayerDepth = 0.0;

        float2 currentTexCoords = texCoords;
        float2 p = viewDir.xy * 0.1;// * sin(curTime) * 10;
        float2 deltaTexCoords = p / numLayers;
        float currentDepthMapValue = 1.0f - tex2D(tNormalBuffer, currentTexCoords).a;

        for( int i = 0; i < numLayers; i++) {
            if (currentLayerDepth >= currentDepthMapValue) break;
            currentTexCoords -= deltaTexCoords;
            currentDepthMapValue = 1.0f - tex2D(tNormalBuffer, currentTexCoords).a;  
            currentLayerDepth += layerDepth;  
        }

        float2 prevTexCoords = currentTexCoords + deltaTexCoords;

        float afterDepth = currentDepthMapValue - currentLayerDepth;
        float beforeDepth = 1.0f - tex2D(tNormalBuffer, prevTexCoords).a - currentLayerDepth + layerDepth;

        float weight = afterDepth / (afterDepth - beforeDepth);
        float2 finalTexCoords = prevTexCoords * weight + currentTexCoords * (1.0 - weight);

        return finalTexCoords;
    }

    float4 main(PS_IN i ) : COLOR
    {
        float3 viewDir = normalize( i.tEyePos - i.tFragPos );// + float3(sin(curTime*0.5), cos(curTime*0.5), 0);
        float2 texCoords = i.vTexCoord;
        texCoords = ParallaxMapping(texCoords, viewDir, i.wNormal);
        // This is for testing below.
        //if(texCoords.x > 1.0 || texCoords.y > 1.0 || texCoords.x < 0.0 || texCoords.y < 0.0) discard;

        float3 normal = pow(tex2D(tNormalBuffer, texCoords), 0.9525);
        normal = normalize( normal * 2.0f - 1.0f);

        float3 color = tex2D(tBaseMap, texCoords);

        float3 ambient = 0.1 * color;

        float3 lightDir = normalize(i.tLightPos - i.tFragPos );// + float3(cos(curTime),sin(curTime),0));
        float diff = max(dot(lightDir, normal), 0.0);
        float3 diffuse = diff * color;
        float3 reflectDir = reflect(-lightDir, normal);
        float3 halfwayDir = normalize(lightDir + viewDir);
        float spec = pow(max(dot(normal, halfwayDir), 0.0), 32);
        
        float3 specular = float3(0.2, 0.2, 0.2) * spec;

        float4 c; c.rgb = ambient + diffuse + specular; c.a = 1;
        return c;
    };


]==])


local shader = shaderlib.NewShader("VertexLitParallax")

-- Shader attribution
shader:SetPixelShader("VertexLitParallax_PixelShader")
shader:SetVertexShader("VertexLitParallax_VertexShader")
-- Binds 
shader:BindTexture(0, PARAM_BASETEXTURE) -- You're free to change this VMT Bind
local plm_normals = shader:AddParam("$plm_normals", SHADER_PARAM_TYPE_TEXTURE, "")
shader:BindTexture(1, plm_normals)

shader:EnableFlashlightSupport(true)

hook.Remove("Think", shader:GetName());
hook.Add("Think", shader:GetName(), function()
	shader:SetPixelShaderConstant(0, CurTime())
end)

shader:SetFlags(0)
shader:SetFlags2(MATERIAL_VAR2_SUPPORTS_HW_SKINNING+MATERIAL_VAR2_LIGHTING_VERTEX_LIT)
local mat = Material("_nfr_/test/floor005a");
/* -- Test Materials List --
    "materials\_nfr_\test\cobble.vtf"
    "materials\_nfr_\test\cobble_height.vtf"
    "materials\_nfr_\test\cobble_normal.vtf"
    "materials\_nfr_\test\face.vtf"
    "materials\_nfr_\test\face_height.vtf"
    "materials\_nfr_\test\face_normal.vtf"
    "materials\_nfr_\test\hole.vtf"
    "materials\_nfr_\test\hole_height.vtf"
    "materials\_nfr_\test\hole_normal.vtf"
    --Unfinished -- "materials\_nfr_\test\moon.vtf"
                    "materials\_nfr_\test\moon_height.vtf"
    "materials\_nfr_\test\parallaxmap_brick.vtf"
    "materials\_nfr_\test\parallaxmap_brick_normal.vtf"
    "materials\_nfr_\test\street.vtf"
    "materials\_nfr_\test\street_normal.vtf"
    "materials\_nfr_\test\water.vtf"
    "materials\_nfr_\test\water_normal.vtf"
    "materials\_nfr_\test\wood.vtf"
    "materials\_nfr_\test\wood_height.vtf"
    "materials\_nfr_\test\wood_normal.vtf"
    "materials\_nfr_\test\woodfloor005a.vtf"
    "materials\_nfr_\test\woodfloor005a_height.vtf"
    "materials\_nfr_\test\woodfloor005a_normal.vtf"
--*/



hook.Remove("PostDrawOpaqueRenderables", shader:GetName())
local pos = LocalPlayer():GetPos() + Vector( 0, 0, 28);

local csModel = ClientsideModel("models/hunter/blocks/cube1x1x1.mdl");
csModel:SetNoDraw(true)
csModel:SetPos(pos);
csModel:SetModelScale(1)


hook.Add("PostDrawOpaqueRenderables", shader:GetName(), function()
	render.MaterialOverride(mat)
    render.SetMaterial(mat)
    csModel:SetAngles(Angle( 0, math.sin(CurTime()*0.04)*180, 0))
    csModel:DrawModel();
    render.MaterialOverride(nil)
end )
