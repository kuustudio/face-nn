// Copyright 2018- PWRD, Inc. All Rights Reserved.
#ifndef PBS_LIGHTING_INCLUDE
#define PBS_LIGHTING_INCLUDE

#include "BRDF.hlsl" 
#include "SH.hlsl"
#include "DebugHead.hlsl"
#include "AddLighting.hlsl"
#include "TerrainWater.hlsl"





//x light intensity y ambientScale
TEXCUBE_SAMPLERCUBE(_EnvCubemap);
FLOAT4 _EnvCubemapParam;//xyz hdr decode w maxMip
FLOAT4 _LightmapScale;
#define _LightmapShadowMask _LightmapScale.x
#define _LightmapShadowMaskInv _LightmapScale.y
#define _ShadowIntensity _LightmapScale.z
TEXTURE2D_SAMPLER2D(_LookupDiffuseSpec);
// #ifndef _NO_RIM
// FLOAT4 _Rim;//x:RimIntensity y:RimWidth
// #endif
// FLOAT4 _CameraPointLight;
FLOAT4 glstate_lightmodel_ambient;

// #if defined(_PBS_FROM_PARAM)&&(defined(LIGHTMAP_ON)||defined(_CUSTOM_LIGHTMAP_ON))
// #define _SIMPLE_LIGHTING
// #endif


FLOAT3 GetAmbient(FFragData FragData, FMaterialData MaterialData)
{
	//return glstate_lightmodel_ambient.xyz *2*_AmbientParam.x;
	return ShadeSHPerPixel(MaterialData.WorldNormal, FragData.Ambient, FragData.WorldPosition)*_AmbientParam.x;
	// #if defined(_DOUBLE_LIGHTS) ||defined (LIGHTMAP_ON)||defined(_CUSTOM_LIGHTMAP_ON)
	// 	IndirectDiffuseLighting = ShadeSHPerPixel(MaterialData.WorldNormal, FragData.Ambient, FragData.WorldPosition)*_AmbientParam.x;
	// #else
	// 	#if !defined(LIGHTMAP_ON)&&!defined(_CUSTOM_LIGHTMAP_ON)
	// 		IndirectDiffuseLighting = ShadeSHPerPixel(MaterialData.WorldNormal, FragData.Ambient, FragData.WorldPosition);
	// 		#ifndef _STATIC_LIGHT
	// 			Float ambientAdd = _AmbientParam.y * smoothstep(-0.9, _AmbientParam.x*2, -FixNdotL);
	// 			//Float ambientAdd = lerp(_AmbientParam.y,_AmbientParam.x,FixNdotL);
	// 			IndirectDiffuseLighting *= ambientAdd;
	// 		#endif//_STATIC_LIGHT
	// 	#endif
	// #endif


	// return IndirectDiffuseLighting;
}



FLightingData GetLighting(FFragData FragData,FMaterialData MaterialData DEBUG_PBS_ARGS)
{
	DECLARE_OUTPUT(FLightingData, LightingData)

#ifndef _UN_LIGHT
	LightingData.DirectLightDir = GetLightDir(FragData);
	FLOAT lightAtten = GetLightingAtten(FragData);

	LightingData.DirectLightColor = GetLightColor0()*lightAtten;

	LightingData.NdotL = dot(MaterialData.WorldNormal, LightingData.DirectLightDir);
	LightingData.FixNdotL = saturate(LightingData.NdotL);
	LightingData.NdotC =  saturate(dot(MaterialData.WorldNormal, FragData.CameraVector));
	LightingData.H = SafeNormalize(FragData.CameraVector + LightingData.DirectLightDir);
	LightingData.NdotH =  saturate(dot(MaterialData.WorldNormal, LightingData.H));
	LightingData.VdotH = saturate(dot(LightingData.DirectLightDir, LightingData.H));

	#ifdef _DOUBLE_LIGHTS
		FLOAT3 DirectLightDir1 = GetLightDir1();
		FLOAT3 DirectLightColor1 =  GetLightColor1();
		LightingData.DirectLightColor1 = DirectLightColor1;
		FLOAT NdotL1 = dot(MaterialData.WorldNormal, DirectLightDir1);
		LightingData.NdotL1=NdotL1;

		LightingData.FixNdotL1 =  saturate(NdotL1);
		LightingData.H1 = SafeNormalize(FragData.CameraVector + DirectLightDir1);
		LightingData.NdotH1 =  saturate(dot(MaterialData.WorldNormal, LightingData.H1));
		LightingData.VdotH1 = saturate(dot(DirectLightDir1, LightingData.H1));
	#endif//_DOUBLE_LIGHTS


#ifndef _ADDLIGHTING
	LightingData.IndirectDiffuseLighting = GetAmbient(FragData, MaterialData);
#endif
	DEBUG_PBS_CUSTOMDATA_PARAM(AmbientDiffuse, LightingData.IndirectDiffuseLighting)
#ifndef _NO_VERTEX_POINTLIGHT
	// LightingData.IndirectPointLight = FragData.VertexPointLight;
#endif//_NO_VERTEX_POINTLIGHT

	#ifdef _PLANE_LIGHT
		LightingData.lighting0 = FLOAT3(1,1,1);
	#else
		LightingData.lighting0 = LightingData.DirectLightColor*LightingData.FixNdotL;				
	#endif

	#ifdef _DOUBLE_LIGHTS
		LightingData.lighting1 = DirectLightColor1*LightingData.FixNdotL1;
	#endif//_DOUBLE_LIGHTS

	FLOAT3 pointDir =  _PointLightPos0.xyz - FragData.WorldPosition;
	FLOAT distDelta = _PointLightPos0.w - dot(pointDir,pointDir);
	distDelta *=_PointLightColor0.w;
	FLOAT distMask = saturate(distDelta)*(distDelta+1-distDelta*0.5);
	FLOAT3 pointDirNormal = normalize(pointDir);
	FLOAT pointNdotL =  saturate(dot(MaterialData.WorldNormal, pointDirNormal));

	#ifdef _SCENE_EFFECT
		LightingData.pointLighting = _PointLightColor0.xyz*pointNdotL*distMask*0.8f;
	#else//!_SCENE_EFFECT
		LightingData.pointLighting = _PointLightColor0.xyz*pointNdotL*distMask;
	#endif//_SCENE_EFFECT

	#ifndef _FULL_SSS
		LightingData.DiffuseColor = MaterialData.BlendColor - MaterialData.BlendColor * MaterialData.Metallic;	// 1 mad
		#ifndef _NO_DEFAULT_SPEC
			FLOAT DielectricSpecular = 0.04;
			LightingData.SpecularColor = DielectricSpecular - DielectricSpecular * MaterialData.Metallic.xxx + MaterialData.BlendColor.rgb*MaterialData.Metallic*_SpecularScale;	// 2 mad
			LightingData.SpecularColor = EnvBRDFApprox(LightingData.SpecularColor, MaterialData.Roughness, LightingData.NdotC);
		#endif
	#else//!_FULL_SSS
		LightingData.DiffuseColor = MaterialData.BlendColor;
	#endif//_FULL_SSS
	
	#if !defined(LIGHTMAP_ON)&&!defined(_CUSTOM_LIGHTMAP_ON)
		#ifdef _VOXEL_LIGHT
			LightingData.pointLighting += GetVoxelLighting(FragData,MaterialData,LightingData);
		#endif//_VOXEL_LIGHT
	#endif// !(LIGHTMAP_ON)&&!(_CUSTOM_LIGHTMAP_ON)

#else//!_UN_LIGHT
	LightingData.DiffuseColor = MaterialData.BlendColor;
#endif//_UN_LIGHT
	LightingData.Shadow = GetAddShadow(FragData)*MaterialData.Shadow;
	DEBUG_PBS_CUSTOMDATA_PARAM(Shadow, LightingData.Shadow)

	return LightingData;
}


// FLightingData GetUnLighting(FFragData FragData, FMaterialData MaterialData DEBUG_PBS_ARGS)
// {
// 	DECLARE_OUTPUT(FLightingData, LightingData)
// #ifndef _FULL_SSS
// 	LightingData.DiffuseColor = MaterialData.BlendColor *(1 - MaterialData.Metallic);	// 1 mad
// #endif//_FULL_SSS

// 	LightingData.Shadow = GetAddShadow(FragData)*MaterialData.Shadow;
// 	DEBUG_PBS_CUSTOMDATA_PARAM(Shadow, LightingData.Shadow)

// 	LightingData.IndirectDiffuseLighting = GetAmbient(FragData, MaterialData, 0);
// 	DEBUG_PBS_CUSTOMDATA_PARAM(AmbientDiffuse, LightingData.IndirectDiffuseLighting)
	
// 	return LightingData;
// }

#if defined(_FULL_SSS)||defined(_PART_SSS)||defined(_DOUBLE_LIGHTS)
FLOAT CalcSpecular_SSS(FLOAT Roughness, FLOAT NoH, FLOAT3 H, FLOAT3 N)
{
	//GGX_Mobile
	FLOAT3 NxH = cross(N, H);
	FLOAT OneMinusNoHSqr = dot(NxH, NxH);

	FLOAT a = max(0.01,Roughness * Roughness);
	FLOAT n = NoH * a;
	FLOAT p = a / (OneMinusNoHSqr + n * n);
	FLOAT d = p * p;

	return (Roughness*_SpecularIntensity*0.1 + _SpecularIntensity*0.1) * min(d, 65504);
}

#endif

#ifndef _FULL_SSS
//FLOAT PhongApprox(FLOAT Roughness, FLOAT RdotL)
//{
//	FLOAT a = Roughness * Roughness;			// 1 mul
//											//!! Ronin Hack?
//	a = max(a, 0.008);						// avoid underflow in FP16, next sqr should be bigger than 6.1e-5
//	FLOAT a2 = a * a;						// 1 mul
//	FLOAT rcp_a2 = rcp(a2);					// 1 rcp
//											//half rcp_a2 = exp2( -6.88886882 * Roughness + 6.88886882 );
//
//											// Spherical Gaussian approximation: pow( x, n ) ~= exp( (n + 0.775) * (x - 1) )
//											// Phong: n = 0.5 / a2 - 0.5
//											// 0.5 / ln(2), 0.275 / ln(2)
//	FLOAT c = 0.72134752 * rcp_a2 + 0.39674113;	// 1 mad
//	FLOAT p = rcp_a2 * exp2(c * RdotL - c);		// 2 mad, 1 exp2, 1 mul
//												// Total 7 instr
//	return min(p, rcp_a2);						// Avoid overflow/underflow on Mali GPUs
//}


// FLOAT EnergyNormalization( inout FLOAT a2, FLOAT VoH)
// {
// 	// if( AreaLight.SphereSinAlphaSoft > 0 )
// 	// {
// 	// 	// Modify Roughness
// 	// 	a2 = saturate( a2 + Pow2( AreaLight.SphereSinAlphaSoft ) / ( VoH * 3.6 + 0.4 ) );
// 	// }

// 	FLOAT Sphere_a2 = a2;
// 	FLOAT Energy = 1;
// 	// if( AreaLight.SphereSinAlpha > 0 )
// 	// {
// 	// 	Sphere_a2 = New_a2( a2, AreaLight.SphereSinAlpha, VoH );
// 	// 	Energy = a2 / Sphere_a2;
// 	// }

// 	if( AreaLight.LineCosSubtended < 1 )
// 	{
// #if 1
// 		float LineCosTwoAlpha = AreaLight.LineCosSubtended;
// 		float LineTanAlpha = sqrt( ( 1.0001 - LineCosTwoAlpha ) / ( 1 + LineCosTwoAlpha ) );
// 		float Line_a2 = New_a2( Sphere_a2, LineTanAlpha, VoH );
// 		Energy *= sqrt( Sphere_a2 / Line_a2 );
// #else
// 		float LineCosTwoAlpha = AreaLight.LineCosSubtended;
// 		float LineSinAlpha = sqrt( 0.5 - 0.5 * LineCosTwoAlpha );
// 		float Line_a2 = New_a2( Sphere_a2, LineSinAlpha, VoH );
// 		Energy *= Sphere_a2 / Line_a2;
// #endif
// 	}

// 	return Energy;
// }

// FLOAT3 SpecularGGX( FLOAT Roughness, FLOAT3 SpecularColor, FLightingData LightingData )
// {
// 	FLOAT a2 = Pow4( Roughness );
// 	// FLOAT Energy = EnergyNormalization( a2, Context.VoH, AreaLight );
	
// 	// Generalized microfacet specular
// 	FLOAT D = D_GGX( a2, LightingData.NdotH );
// 	FLOAT Vis = Vis_SmithJointApprox( a2, LightingData.NdotC, LightingData.NdotL );
// 	FLOAT3 F = F_Schlick( SpecularColor, LightingData.VdotH );

// 	return (D * Vis) * F;
// }

#if defined(LIGHTMAP_ON)||defined(_CUSTOM_LIGHTMAP_ON)
TEXTURE2D_SAMPLER2D(unity_Lightmap);
// FLOAT4 unity_Lightmap_HDR;

inline FLOAT3 DecodeLightmap(FLOAT4 color)
{
#if defined(UNITY_LIGHTMAP_DLDR_ENCODING)//mobile
	// #if defined(_GRASS_LIGHT)
	// 	return color.rgb*4.59f;
	// #else
    	return color.rgb*4.59f;//pow(2.0,2.2);		
	// #endif
#elif defined(UNITY_LIGHTMAP_RGBM_ENCODING)//pc
    return (34.49 * pow(color.a, 2.2)) * color.rgb;//x=pow(5.0,2.2);y=2.2
#else //defined(UNITY_LIGHTMAP_FULL_HDR)
    return color.rgb;
#endif
}
#endif

// FLOAT3 GetGIMask(FLightingData LightingData)
// {
// 	#if defined(LIGHTMAP_ON)||defined(_CUSTOM_LIGHTMAP_ON)
// 		return LightingData.gi.w;
// 	#else
// 		return 1;
// 	#endif
// }

// FLOAT3 GetGI(FLightingData LightingData)
// {
// 	#if defined(LIGHTMAP_ON)||defined(_CUSTOM_LIGHTMAP_ON)
// 		return LightingData.gi*LightingData.DiffuseColor;//*LightingData.lighting0;
// 	#else
// 		return 0;
// 	#endif
// }

#include "TreeLighting.hlsl"
#include "WaterLighting.hlsl"

//Lighting Model Type
void ShadingMode(FFragData FragData, FMaterialData MaterialData, FLightingData LightingData,inout FLOAT3 DirectDiffuse,inout FLOAT3 DirectSpecular DEBUG_PBS_ARGS)
{
	#ifdef _UN_LIGHT
		DirectDiffuse = LightingData.Shadow*LightingData.DiffuseColor;
		DirectSpecular = FLOAT3(0,0,0);		
	#elif defined(_STANDARD_LIGHT)
		#ifdef _SIMPLE_LIGHTING
			FLOAT3 diffuseTerm = Diffuse_Burley( LightingData.DiffuseColor,MaterialData.Roughness,LightingData.NdotC,LightingData.FixNdotL,LightingData.VdotH);
			DirectDiffuse = LightingData.Shadow*diffuseTerm*LightingData.gi.w;
			DirectDiffuse += LightingData.gi.xyz;
		#else//!_SIMPLE_LIGHTING
			#ifdef _DOUBLE_LIGHTS
				FLOAT forawrdCalc = Pow5( 1 - LightingData.NdotC );

				FLOAT3 diffuse0 = Diffuse_Burley(MaterialData.Roughness,LightingData.FixNdotL,LightingData.VdotH,forawrdCalc);
				FLOAT3 diffuse1 = Diffuse_Burley(MaterialData.Roughness,LightingData.FixNdotL1,LightingData.VdotH1,forawrdCalc);		
				DirectDiffuse = LightingData.Shadow*LightingData.DiffuseColor*diffuse0*LightingData.lighting0*LightingData.gi.w;
				DirectDiffuse += LightingData.Shadow*LightingData.DiffuseColor*diffuse1*LightingData.lighting1;
				DEBUG_PBS_CUSTOMDATA_PARAM(DirectDiffuseNoGI, DirectDiffuse)
				DirectDiffuse += LightingData.gi.xyz;
				#ifndef _NO_DEFAULT_SPEC
					FLOAT a = max(0.01,MaterialData.Roughness * MaterialData.Roughness);				
					FLOAT param = MaterialData.Roughness * MaterialData.MetallicScale + MaterialData.MetallicScale;
					FLOAT spec0 = CalcSpecular(a,LightingData.NdotH, LightingData.H, MaterialData.WorldNormal,param);
					FLOAT spec1 = CalcSpecular(a,LightingData.NdotH1, LightingData.H1, MaterialData.WorldNormal,param);
					DirectSpecular = LightingData.SpecularColor * (spec0 * LightingData.lighting0*LightingData.gi.w + spec1 * LightingData.lighting1);

				#ifdef _SCENE_EFFECT
					DirectSpecular = LightingData.SpecularColor * (spec0 * LightingData.lighting0*LightingData.gi.w + spec1 * LightingData.lighting1);	
				#else
					FLOAT3 CLightH = SafeNormalize(FragData.CameraVector);
					FLOAT CLightNoH = saturate(dot(MaterialData.WorldNormal, CLightH));
					FLOAT specPoint = CalcSpecular(a,CLightNoH, CLightH, MaterialData.WorldNormal,param);
					DirectSpecular = LightingData.SpecularColor * max(spec0 * LightingData.lighting0*LightingData.gi.w + spec1 * LightingData.lighting1,specPoint*LightingData.NdotC*0.5);
				#endif//_SCENE_EFFECT
				
				// 地形上的水 //
				#if defined(_TERRAIN_WATER)
				{
					TerrainWaterLighting(FragData, MaterialData, DirectDiffuse, DirectSpecular);
				}
				#endif


					//DirectSpecular = min(5, DirectSpecular);
				#endif//!_NO_DEFAULT_SPEC
			#else//!_DOUBLE_LIGHTS
					FLOAT3 diffuseTerm = Diffuse_Burley( LightingData.DiffuseColor,MaterialData.Roughness,LightingData.NdotC,LightingData.FixNdotL,LightingData.VdotH);
					DirectDiffuse = LightingData.Shadow*diffuseTerm*LightingData.lighting0*LightingData.gi.w;
					DEBUG_PBS_CUSTOMDATA_PARAM(DirectDiffuseNoGI, DirectDiffuse)
					DirectDiffuse += LightingData.gi.xyz;
				#ifndef _NO_DEFAULT_SPEC
					DirectSpecular = LightingData.SpecularColor * CalcSpecular(MaterialData.Roughness, LightingData.NdotH, LightingData.H, MaterialData.WorldNormal)*LightingData.lighting0*LightingData.gi.w;
					//DirectSpecular = min(5, DirectSpecular);
				#endif
			#endif//_DOUBLE_LIGHTS
		#endif//_SIMPLE_LIGHTING		
	#elif defined(_GRASS_LIGHT)
		DirectDiffuse = LightingData.Shadow * LightingData.DiffuseColor * LightingData.lighting0*LightingData.gi.w;
		// DirectDiffuse += LightingData.Shadow * LightingData.gi * LightingData.DiffuseColor;
		DirectDiffuse.rgb = lerp(DirectDiffuse.rgb, 0, (1.0 - FragData.GrassOcc) * _Occ_Scale);
	#elif defined(_WATER_LIGHT)
		WaterShadingMode(FragData,MaterialData,LightingData,DirectDiffuse,DirectSpecular DEBUG_PBS_PARAM);
	#elif defined(_TREE_LIGHT_)
		TreeShadingMode(FragData,MaterialData,LightingData,DirectDiffuse,DirectSpecular DEBUG_PBS_PARAM);
	#elif defined(_CUSTOM_LIGHT_)
		CustomShadingMode(FragData,MaterialData,LightingData,DirectDiffuse,DirectSpecular DEBUG_PBS_PARAM);
	#endif	
	
}

FLOAT3 GetDirectLighting(FFragData FragData, FMaterialData MaterialData, FLightingData LightingData DEBUG_PBS_ARGS)
{
	FLOAT3 DirectDiffuse = FLOAT3(0, 0, 0);
	FLOAT3 DirectSpecular = FLOAT3(0, 0, 0);
	FLOAT3 color = FLOAT3(0, 0, 0);
	LightingData.gi = FLOAT4(0,0,0,1);
	#ifdef _UN_LIGHT
		color = LightingData.Shadow*LightingData.DiffuseColor;
	#else//!_UN_LIGHT
		#if defined(LIGHTMAP_ON)||defined(_CUSTOM_LIGHTMAP_ON)			
			if(_LightMapEnable)
			{
				FLOAT4 bakedColorTex = SAMPLE_TEXTURE2D(unity_Lightmap, GET_FRAG_LIGTHMAP_UV);
				FLOAT3 lightmapLighting = DecodeLightmap(bakedColorTex);
				DEBUG_PBS_CUSTOMDATA_PARAM(LightMapColor, lightmapLighting.rgb)
				FLOAT shadow = 1-(1-LightingData.Shadow)*saturate(lightmapLighting.r+ lightmapLighting.g+ lightmapLighting.b);
				LightingData.gi.xyz = LightingData.Shadow*max(0.5,LightingData.Shadow)* lightmapLighting*(shadow+1)*0.5*LightingData.DiffuseColor;
				LightingData.gi.w = saturate(saturate(Luminance(bakedColorTex.rgb)*_LightmapShadowMask-1) + _ShadowIntensity);
				DEBUG_PBS_CUSTOMDATA_PARAM(LightMapGI, LightingData.gi)
			}

			ShadingMode(FragData,MaterialData,LightingData,DirectDiffuse,DirectSpecular DEBUG_PBS_PARAM);
		#else //!(LIGHTMAP_ON||_CUSTOM_LIGHTMAP_ON)
			ShadingMode(FragData,MaterialData,LightingData,DirectDiffuse,DirectSpecular DEBUG_PBS_PARAM);
		#endif	//LIGHTMAP_ON||_CUSTOM_LIGHTMAP_ON
			#ifdef _DOUBLE_LIGHTS
				DEBUG_PBS_CUSTOMDATA_PARAM(DirectLighting, LightingData.lighting0+LightingData.lighting1)
			#else
				DEBUG_PBS_CUSTOMDATA_PARAM(DirectLighting, LightingData.lighting0)
			#endif
			DEBUG_PBS_CUSTOMDATA_PARAM(DirectDiffuse, DirectDiffuse)
			DEBUG_PBS_CUSTOMDATA_PARAM(DirectSpecular, DirectSpecular)
			color = DirectDiffuse + (LightingData.IndirectDiffuseLighting + LightingData.pointLighting)*LightingData.DiffuseColor;
			color += DirectSpecular;
			DEBUG_PBS_CUSTOMDATA_PARAM(DirectLightingColor, color)

		#if defined(_ETX_EFFECT)&&!defined(_SCENE_EFFECT)
			color *= saturate(AOMultiBounce(MaterialData.BlendColor,MaterialData.EmissiveAO.a,_Emi_Color.w)); 
		#endif //_ETX_EFFECT
	#endif//_UN_LIGHT
	return color;
}

FLOAT3 GetImageBasedReflectionLighting(FFragData FragData,FMaterialData MaterialData, FLightingData LightingData DEBUG_PBS_ARGS)
{

	// Compute fractional mip from roughness
	//FLOAT AbsoluteSpecularMip = _EnvCubemapParam.w - 2 - 1.2 * log2(MaterialData.Roughness);
	FLOAT r = sqrt(MaterialData.Roughness);
	FLOAT AbsoluteSpecularMip = r * (1.7 - 0.7 * r) * _EnvCubemapParam.w;
	FLOAT3 viewDir = FragData.WorldPosition_CamRelative;

	DEBUG_PBS_CUSTOMDATA_PARAM(CubeMipmap, AbsoluteSpecularMip)
	// Fetch from cubemap and convert to linear HDR
	FLOAT3 SpecularIBL = DecodeHDR(SAMPLE_TEXCUBE_LOD(_EnvCubemap, MaterialData.ReflectionVector, AbsoluteSpecularMip), _EnvCubemapParam.xyz);

	FLOAT surfaceReduction = 1.0 / (Pow4(MaterialData.Roughness) + 1.0);
	SpecularIBL = lerp(0.5, 0.8 , MaterialData.Metallic)*SpecularIBL*lerp(0.45,1,MaterialData.Metallic)*0.75;
	FLOAT grazingTerm = saturate(1.36 - r + 0.64*MaterialData.Metallic)*0.25;
	FLOAT3 lighting = surfaceReduction * SpecularIBL * FresnelLerp(LightingData.SpecularColor, grazingTerm, LightingData.NdotC)*_IBLScale;
	DEBUG_PBS_CUSTOMDATA_PARAM(ImageBasedReflectionLighting, lighting)

#if defined(_ETX_EFFECT)&&!defined(_SCENE_EFFECT)
	lighting *= saturate( AOMultiBounce(FLOAT3(1,1,1), MaterialData.EmissiveAO.a,_Emi_Color.w));
#endif //_ETX_EFFECT

#ifdef _DOUBLE_LIGHTS
	return (0.5*(LightingData.lighting0 + LightingData.lighting1+ LightingData.IndirectDiffuseLighting + LightingData.pointLighting-1)+1)*lighting;
#else
	return (0.5*(LightingData.lighting0 + LightingData.IndirectDiffuseLighting + LightingData.pointLighting-1)+1)*lighting;
#endif
}

#endif//_FULL_SSS

#ifdef _RIM
//FLOAT4 glstate_lightmodel_ambient;
FLOAT3 GetRimLighting(FMaterialData MaterialData,FLightingData LightingData DEBUG_PBS_ARGS)
{
	FLOAT3 lighting = FLOAT3(0, 0, 0);
	if (_Rim.x > 0.0f)
	{
		FLOAT rim = (pow(saturate((1 - LightingData.NdotC)*(1 - LightingData.NdotL) * _Rim.y), 3)) * _Rim.x;
		lighting = glstate_lightmodel_ambient.rgb*rim;
		DEBUG_PBS_CUSTOMDATA_PARAM(RimLight, lighting)
	}
	return lighting;
}
#endif

void GetCustomLighting(FLightingData LightingData,inout FLOAT3 color, FLOAT4 vertexColor)
{	
	color *= (vertexColor.a < 0.45 ? vertexColor.rgb : FLOAT3(1,1,1));
	color += (vertexColor.a > 0.49 && vertexColor.a < 0.91 ? (Square(saturate(1 - LightingData.NdotC)) * 40 *(vertexColor.a-0.5f) * vertexColor.rgb) : FLOAT3(0,0,0));
}

FLOAT3 GetSkinLighting(FFragData FragData, FMaterialData MaterialData, FLightingData LightingData DEBUG_PBS_ARGS)
{
#ifndef LOW_QUALITY
	FLOAT3 viewDir = FragData.CameraVector;	
	FLOAT CdotH = dot(viewDir, LightingData.H);
	
	FLOAT3 diff = FLOAT3(0,0,0);
	FLOAT4 baseColor = MaterialData.BaseColor;
	FLOAT shadow = 1 - MaterialData.Shadow;
	FLOAT NdotL = LightingData.NdotL;

	FLOAT3 diffHSV = RgbToHsv(baseColor.rgb);
	diffHSV.y *= 0.7 + lerp(0.3,0.4*smoothstep(0.1,2.2,4*(diffHSV.y)*(diffHSV.y)),_ScatteringPower);
	diffHSV.z *= _ScatteringOffset * 0.75;
	baseColor.rgb = HsvToRgb(diffHSV);

	FLOAT  diffNdotL1 = smoothstep(-1,0.25,NdotL - 0.4*shadow); 
	FLOAT  diffNdotL2 = smoothstep(-0.32,1,NdotL - 0.5*shadow);	
	diff = lerp(lerp(FLOAT3(0.6,0.25,0.15)*0.25,FLOAT3(0.9,0.45,0.35)*0.7,diffNdotL1),1.75,diffNdotL2);
	diff *= max(log2(max(max(diff.r,diff.g),diff.b)),0.9);

	#ifdef _DOUBLE_LIGHTS
		FLOAT NdotL1 = LightingData.NdotL1;
		FLOAT3 diff1 = FLOAT3(0,0,0);
		
		FLOAT  diff1NdotL1 = smoothstep(-1,0.25,NdotL1 - 0.4*shadow);
		FLOAT  diff1NdotL2 = smoothstep(-0.32,1,NdotL1 - 0.5*shadow);	
		diff1 = lerp(lerp(FLOAT3(0.6,0.25,0.15)*0.25,FLOAT3(0.9,0.45,0.35)*0.7,diff1NdotL1),1.75,diff1NdotL2);
		diff1 *= max(log2(max(max(diff1.r,diff1.g),diff1.b)),0.9);
	#endif//_DOUBLE_LIGHTS

	DEBUG_PBS_CUSTOMDATA_PARAM(LookupDiffuseSpec, diff)

	// specular
	FLOAT3 specLevel = 0;
	if (_SpecularIntensity > 0.0f)
	{
		FLOAT NdotH = LightingData.NdotH;
		FLOAT H = LightingData.H;
		FLOAT Gloss = _SpecularIntensity - MaterialData.Roughness*_SpecularIntensity;
		FLOAT SkinSpecular = 1- MaterialData.Roughness*_SpecularRoughness;

		FLOAT spec = lerp(smoothstep(-0.25,1,NdotH)*0.2,smoothstep(0.9,1,NdotH)*0.8,SkinSpecular);
		FLOAT PH = Pow10(2.0*spec);

		FLOAT exponential = Pow5(1.0 - CdotH);
		FLOAT fresnelReflectance = exponential + 0.028 * (1.0 - exponential);

		FLOAT frSpec = max(PH * fresnelReflectance * rcp(max(dot(H, H),1e-5)), 0);
			
		specLevel = saturate((LightingData.NdotL - 0.5) * 2 * Gloss * frSpec);

		#ifdef _DOUBLE_LIGHTS
			specLevel= LightingData.DirectLightColor*CalcSpecular_SSS(MaterialData.Roughness*_SpecularRoughness,NdotH,LightingData.H, MaterialData.WorldNormal)*LightingData.FixNdotL;
			FLOAT3 specLevel1 = LightingData.DirectLightColor1*CalcSpecular_SSS(MaterialData.Roughness*_SpecularRoughness,LightingData.NdotH1,LightingData.H1, MaterialData.WorldNormal)*LightingData.FixNdotL1;
			specLevel += specLevel1;	

			FLOAT3 CLightH = SafeNormalize(FragData.CameraVector);
			FLOAT CLightNoH = saturate(dot(MaterialData.WorldNormal, CLightH));
			FLOAT specPoint = CalcSpecular_SSS(MaterialData.Roughness*_SpecularRoughness,CLightNoH, CLightH, MaterialData.WorldNormal);
			specLevel =max(specLevel, specPoint*LightingData.NdotC*0.5);
			
		#endif

	}
	DEBUG_PBS_CUSTOMDATA_PARAM(SpecLevel, specLevel)

	FLOAT3 skin =  LightingData.DirectLightColor*diff + LightingData.pointLighting + LightingData.IndirectDiffuseLighting;
	#ifdef _DOUBLE_LIGHTS
		skin += LightingData.DirectLightColor1*diff1;
	#endif
	
	skin *= baseColor.rgb + specLevel;
	return min(5,skin);

#else
	FLOAT3 skin = MaterialData.BaseColor.rgb*LightingData.DirectLightColor * (1+LightingData.IndirectDiffuseLighting+ LightingData.pointLighting);
	return skin;
#endif
}

// uint ExtractSubsurfaceProfileInt(FGBufferData BufferData)
// {
// 	// can be optimized
// 	return uint(BufferData.CustomData.r * 255.0f + 0.5f);
// }
#define SSSS_SUBSURFACE_COLOR_OFFSET			0
#define SSSS_TRANSMISSION_OFFSET				(SSSS_SUBSURFACE_COLOR_OFFSET+1)
#define SSSS_BOUNDARY_COLOR_BLEED_OFFSET		(SSSS_TRANSMISSION_OFFSET+1)
#define SSSS_DUAL_SPECULAR_OFFSET				(SSSS_BOUNDARY_COLOR_BLEED_OFFSET+1)
#define SSSS_KERNEL0_OFFSET						(SSSS_DUAL_SPECULAR_OFFSET+1)
#define SSSS_KERNEL0_SIZE						13
#define SSSS_KERNEL1_OFFSET						(SSSS_KERNEL0_OFFSET + SSSS_KERNEL0_SIZE)
#define SSSS_KERNEL1_SIZE						9
#define SSSS_KERNEL2_OFFSET						(SSSS_KERNEL1_OFFSET + SSSS_KERNEL1_SIZE)
#define SSSS_KERNEL2_SIZE						6
#define SSSS_KERNEL_TOTAL_SIZE					(SSSS_KERNEL0_SIZE + SSSS_KERNEL1_SIZE + SSSS_KERNEL2_SIZE)
#define SSSS_TRANSMISSION_PROFILE_OFFSET		(SSSS_KERNEL0_OFFSET + SSSS_KERNEL_TOTAL_SIZE)
#define SSSS_TRANSMISSION_PROFILE_SIZE			32
#define	SSSS_MAX_TRANSMISSION_PROFILE_DISTANCE	5.0f // See MaxTransmissionProfileDistance in ComputeTransmissionProfile(), SeparableSSS.cpp
#define SSSS_MAX_DUAL_SPECULAR_ROUGHNESS		2.0f

TEXTURE2D_SAMPLER2D(SSProfilesTexture);

void GetProfileDualSpecular( out FLOAT AverageToRoughness0, out FLOAT AverageToRoughness1, out FLOAT LobeMix)
{
	// 0..255, which SubSurface profile to pick
	uint SubsurfaceProfileInt = 1;//ExtractSubsurfaceProfileInt(GBuffer);

	FLOAT4 Data = SAMPLE_TEXTURE2D(SSProfilesTexture,int2(SSSS_DUAL_SPECULAR_OFFSET, SubsurfaceProfileInt));
	AverageToRoughness0 = Data.x * SSSS_MAX_DUAL_SPECULAR_ROUGHNESS;
	AverageToRoughness1 = Data.y * SSSS_MAX_DUAL_SPECULAR_ROUGHNESS;
	LobeMix = Data.z;
}
// FLOAT3 DualSpecularGGX(FLOAT AverageRoughness, FLOAT Lobe0Roughness, FLOAT Lobe1Roughness, FLOAT LobeMix, FLOAT3 SpecularColor, FLOAT NoL)
// {
// 	FLOAT AverageAlpha2 = Pow4(AverageRoughness);
// 	FLOAT Lobe0Alpha2 = Pow4(Lobe0Roughness);
// 	FLOAT Lobe1Alpha2 = Pow4(Lobe1Roughness);

// 	FLOAT Lobe0Energy = EnergyNormalization(Lobe0Alpha2, Context.VoH, AreaLight);
// 	FLOAT Lobe1Energy = EnergyNormalization(Lobe1Alpha2, Context.VoH, AreaLight);

// 	// Generalized microfacet specular
// 	FLOAT D = lerp(D_GGX(Lobe0Alpha2, Context.NoH) * Lobe0Energy, D_GGX(Lobe1Alpha2, Context.NoH) * Lobe1Energy, LobeMix);
// 	FLOAT Vis = Vis_SmithJointApprox(AverageAlpha2, Context.NoV, NoL); // Average visibility well approximates using two separate ones (one per lobe).
// 	FLOAT3 F = F_Schlick(SpecularColor, Context.VoH);

// 	return (D * Vis) * F;
// }

FLOAT3 SubsurfaceProfileBxDF(FFragData FragData, FMaterialData MaterialData, FLightingData LightingData DEBUG_PBS_ARGS)
{
	// BxDFContext Context;
	// Init( Context, N, V, L );
	// SphereMaxNoH( Context, AreaLight.SphereSinAlpha, true );
	// Context.NoV = saturate( abs( Context.NoV ) + 1e-5 );

	FLOAT AverageToRoughness0;
	FLOAT AverageToRoughness1;
	FLOAT LobeMix;
	GetProfileDualSpecular(AverageToRoughness0, AverageToRoughness1, LobeMix);

	FLOAT AverageRoughness = MaterialData.Roughness;
	FLOAT Lobe0Roughness = max(saturate(AverageRoughness * AverageToRoughness0), 0.02f);
	FLOAT Lobe1Roughness = saturate(AverageRoughness * AverageToRoughness1);

	// Smoothly lerp to default single GGX lobe as Opacity approaches 0, before reverting to SHADINGMODELID_DEFAULT_LIT.
	// See SUBSURFACE_PROFILE_OPACITY_THRESHOLD in ShadingModelsMaterial.ush.
	FLOAT Opacity = 0.5;//GBuffer.CustomData.a;
	Lobe0Roughness = lerp(1.0f, Lobe0Roughness, saturate(Opacity * 10.0f));
	Lobe1Roughness = lerp(1.0f, Lobe1Roughness, saturate(Opacity * 10.0f));

	FLOAT3 lighting = LightingData.Shadow * LightingData.DirectLightColor* LightingData.NdotL;	
	FLOAT3 DirectDiffuse  = lighting * Diffuse_Burley( LightingData.DiffuseColor,MaterialData.Roughness,LightingData.NdotC,LightingData.NdotL,LightingData.VdotH) + LightingData.IndirectDiffuseLighting*LightingData.DiffuseColor;
	//FLOAT3 DirectSpecular = lighting * DualSpecularGGX(AverageRoughness, Lobe0Roughness, Lobe1Roughness, LobeMix, GBuffer.SpecularColor, Context, NoL, AreaLight);
	FLOAT3 DirectSpecular = FLOAT3(0, 0, 0);
	DEBUG_PBS_CUSTOMDATA_PARAM(DirectDiffuse, DirectDiffuse)
	DEBUG_PBS_CUSTOMDATA_PARAM(DirectSpecular, DirectSpecular)
	lighting =  DirectDiffuse + DirectSpecular;
	DEBUG_PBS_CUSTOMDATA_PARAM(DirectLightingColor, lighting)
	return lighting;

// #if USE_TRANSMISSION

// 	FTransmissionProfileParams TransmissionParams = GetTransmissionProfileParams( GBuffer );

// 	float Thickness = Shadow.TransmissionThickness;
// 	Thickness = DecodeThickness(Thickness);
// 	Thickness *= SSSS_MAX_TRANSMISSION_PROFILE_DISTANCE;
// 	float3 Profile = GetTransmissionProfile(GBuffer, Thickness).rgb;

// 	float3 RefracV = refract(V, -N, TransmissionParams.OneOverIOR);
// 	float PhaseFunction = ApproximateHG( dot(-L, RefracV), TransmissionParams.ScatteringDistribution );
// 	Lighting.Transmission = AreaLight.FalloffColor * Profile * (Falloff * PhaseFunction); // TODO: This probably should also include cosine term (NoL)

// #else // USE_TRANSMISSION

// 	Lighting.Transmission = 0;

// #endif // USE_TRANSMISSION
}
#endif //PBS_LIGHTING_INCLUDE