#version 450 core
out vec4 FragColor;

in vec2 fragTexcoords;

uniform sampler2D gWorldPos;
uniform sampler2D gWorldNormal;
uniform sampler2D gAlbedo;
uniform sampler2D gRoughnessMetalnessAo;
uniform sampler2D gEmission;
uniform sampler2D gDepth;

uniform vec3 cameraPos;

uniform samplerCube irradianceMap;
uniform samplerCube prefilterMap;
uniform sampler2D brdfLUT;

uniform mat4 lightSpaceMatrix;
uniform sampler2D shadowMap;

// Directional light struct
struct DirectionalLight 
{
    vec3 direction;
    vec3 color;
    float intensity;
};

// Point light struct
struct PointLight 
{
    vec3 position;
    vec3 color;
    float intensity;
    float constant;
    float linear;
    float quadratic;
    float radius;
};

// Spot light struct
struct SpotLight 
{
    vec3 position;
    vec3 direction;
    vec3 color;
    float intensity;
    float constant;
    float linear;
    float quadratic;
    float innerCutoff;
    float outerCutoff;
};

// define MAX POINT LIGHTS
#define MAX_POINT_LIGHTS 100
#define MAX_SPOT_LIGHTS 100

// PCSS
#define BLOCKER_SEARCH_NUM_SAMPLES 16
#define PCF_NUM_SAMPLES 16 

vec2 poissonDisk[16] = 
{
     vec2( -0.94201624, -0.39906216 ),
     vec2( 0.94558609, -0.76890725 ),
     vec2( -0.094184101, -0.92938870 ),
     vec2( 0.34495938, 0.29387760 ),
     vec2( -0.91588581, 0.45771432 ),
     vec2( -0.81544232, -0.87912464 ),
     vec2( -0.38277543, 0.27676845 ),
     vec2( 0.97484398, 0.75648379 ),
     vec2( 0.44323325, -0.97511554 ),
     vec2( 0.53742981, -0.47373420 ),
     vec2( -0.26496911, -0.41893023 ),
     vec2( 0.79197514, 0.19090188 ),
     vec2( -0.24188840, 0.99706507 ),
     vec2( -0.81409955, 0.91437590 ),
     vec2( 0.19984126, 0.78641367 ),
     vec2( 0.14383161, -0.14100790 )
 };

uniform DirectionalLight directionalLight;
uniform PointLight pointLights[MAX_POINT_LIGHTS];
uniform int activePointLights;
uniform SpotLight spotLights[MAX_SPOT_LIGHTS];

const float PI = 3.14159265359;

float DistributionGGX(vec3 N, vec3 H, float a)
{
    float a2     = a*a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;
	
    float nom    = a2;
    float denom  = (NdotH2 * (a2 - 1.0) + 1.0);
    denom        = PI * denom * denom + 0.0001;
	
    return nom / denom;
}

float GeometrySchlickGGX(float NdotV, float k)
{
    float nom   = NdotV;
    float denom = NdotV * (1.0 - k) + k  + 0.0001;
	
    return nom / denom;
}
  
float GeometrySmith(vec3 N, vec3 V, vec3 L, float k)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx1 = GeometrySchlickGGX(NdotV, k);
    float ggx2 = GeometrySchlickGGX(NdotL, k);
	
    return ggx1 * ggx2;
}

// From UE4
vec3 fresnelSchlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(2, ((-5.55473 * cosTheta) - 6.68316) * cosTheta);
}

vec3 fresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness)
{
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(2, ((-5.55473 * cosTheta) - 6.68316) * cosTheta);;
}  

vec3 CalcDirectionalLight(DirectionalLight light, vec3 N, vec3 V, 
    vec3 albedo, float roughness, float metalness, vec3 F0)
{
    vec3 L = normalize(light.direction);
    vec3 H = normalize(V + L);
    vec3 radiance = light.color * light.intensity;
        
    // cook-torrance brdf
    float D = DistributionGGX(N, H, roughness);        
    float G   = GeometrySmith(N, V, L, roughness);      
    vec3 F    = fresnelSchlick(max(dot(H, V), 0.0), F0);       
        
    // Metal has no diffuse component
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - metalness;	  
        
    vec3 numerator    = D * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular     = numerator / denominator;  

    float NdotL = max(dot(N, L), 0.0);   
    return (kD * albedo / PI + specular) * radiance * NdotL;
}

vec3 CalcPointLight(PointLight light, vec3 N, vec3 V, 
    vec3 fragPosWorld, vec3 albedo, float roughness, float metalness, vec3 F0)
{
    vec3 L = normalize(light.position - fragPosWorld);
    vec3 H = normalize(V + L);
    float distance = length(light.position - fragPosWorld);
    float lightRadius = light.radius;
    // Inverse square falloff achieves more natural results
    float falloff = pow(clamp(1.0 - pow(distance / lightRadius, 4.0), 0.0, 1.0), 2.0);
    float attenuation = falloff / (distance * distance + 1.0);
    vec3 radiance = light.color * light.intensity * attenuation;
//    float attenuation = 1.0 / (light.constant + light.linear * distance + light.quadratic * (distance * distance));
//    vec3 radiance = light.color * light.intensity * attenuation;
        
    // cook-torrance brdf
    float NDF = DistributionGGX(N, H, roughness);        
    float G   = GeometrySmith(N, V, L, roughness);      
    vec3 F    = fresnelSchlick(max(dot(H, V), 0.0), F0);       
        
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - metalness;	  
        
    vec3 numerator    = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular     = numerator / denominator;  

    float NdotL = max(dot(N, L), 0.0);   
    return (kD * albedo / PI + specular) * radiance * NdotL;
}

vec3 CalcSpotLight(SpotLight light, vec3 N, vec3 V, 
    vec3 fragPosWorld, vec3 albedo, float roughness, float metalness, vec3 F0)
{
    vec3 L = normalize(light.position - fragPosWorld);
    vec3 H = normalize(V + L);
    float distance = length(light.position - fragPosWorld);
    float attenuation = 1.0 / (light.constant + light.linear * distance + light.quadratic * (distance * distance));

    float theta = dot(light.direction, normalize(-L)); // Angle between light direction and direction to fragment
    float falloff = 1.0;
    if (theta > light.outerCutoff) 
    {
        falloff = (theta - light.outerCutoff) / (light.innerCutoff - light.outerCutoff); // Smooth falloff between inner and outer cones
    } 
    else 
    {
        falloff = 0.0; // Outside the outer cone, no light
    }

    vec3 radiance = light.color * light.intensity * falloff * attenuation;
        
    // cook-torrance brdf
    float NDF = DistributionGGX(N, H, roughness);        
    float G   = GeometrySmith(N, V, L, roughness);      
    vec3 F    = fresnelSchlick(max(dot(H, V), 0.0), F0);       
        
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - metalness;	  
        
    vec3 numerator    = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular     = numerator / denominator;  

    float NdotL = max(dot(N, L), 0.0);   
    return (kD * albedo / PI + specular) * radiance * NdotL;
}

vec3 ToneMapACES(vec3 color)
{
    const float A = 2.51;
    const float B = 0.03;
    const float C = 2.43;
    const float D = 0.59;
    const float E = 0.14;
    return clamp((color * (A * color + B)) / (color * (C * color + D) + E), 0.0, 1.0);
}


float BlockerSearchWidth(float lightSize, float receiverDepth)
{
    float NEAR = 1.0;
    float scale = 1.0;
	return scale * lightSize * (receiverDepth - NEAR) / receiverDepth;
}

float PenumbraSize(float receiverDepth, float blockerDepth, float lightSize) 
{
    return lightSize * (receiverDepth - blockerDepth) / blockerDepth;
}

// blocker search
float FindBlcokerDepth(out float blockerCount, vec2 shadowCoord, float lightSize, float receiverDepth)
{
    blockerCount = 0;
    float avgBlockerDepth = 0.0;

    float searchWidth = BlockerSearchWidth(lightSize, receiverDepth);

    for( int i = 0; i < BLOCKER_SEARCH_NUM_SAMPLES; ++i )
    {
        float z = texture(shadowMap, shadowCoord.xy + poissonDisk[i] * searchWidth).r;
        if( z < receiverDepth )
		{
			avgBlockerDepth += z;
			++blockerCount;
		}
    }

	return avgBlockerDepth;
}

float PCF_Filter( vec2 shadowCoord, float receiverDepth, float radius, float bias )
{
    float sum = 0.0;

    for ( int i = 0; i < PCF_NUM_SAMPLES; ++i )
    {
        vec2 offset = poissonDisk[i] * radius;
        float pcfDepth = texture(shadowMap, shadowCoord.xy + offset).r;
        sum += pcfDepth < receiverDepth - bias ? 1.0 : 0.0;
    }
    return sum / float(PCF_NUM_SAMPLES);
} 

float ShadowCalculation(vec4 fragPosLightSpace, vec3 n, vec3 l)
{
    // perform perspective divide
    vec3 projCoords = fragPosLightSpace.xyz / fragPosLightSpace.w;
    projCoords = projCoords * 0.5 + 0.5;
    float receiverDepth = projCoords.z;
    float lightSize = 0.06;
    float NEAR = 1.0;

    // 1. blocker search
    float blockerCount = 0;
    float averageBlockerDepth = FindBlcokerDepth(blockerCount, projCoords.xy, lightSize, receiverDepth);
    if (blockerCount == 0)
		return 0.0;
    averageBlockerDepth /= blockerCount;

    // 2. estimate penumbra size
    float penumbra = PenumbraSize(receiverDepth, averageBlockerDepth, lightSize);
    float filterRadius = penumbra * lightSize * NEAR / receiverDepth;

    // 3. PCF
    float bias = max(0.05 * (1.0 - dot(n, l)), 0.005);  
    float shadow = PCF_Filter(projCoords.xy, receiverDepth, filterRadius, bias);

    return shadow;
}

vec3 visualizeDepth(float depth)
{
    const float near = 1.0; // Near clipping plane
    const float far = 100.0; // Far clipping plane
    float z = depth * 2.0 - 1.0; // Back to NDC
    float linearDepth = (2.0 * near) / (far + near - z * (far - near));
    return vec3(linearDepth);
}

void main()
{
    vec3 albedo = texture(gAlbedo, fragTexcoords).rgb;
    vec3 normal = texture(gWorldNormal, fragTexcoords).rgb;
    vec3 worldPosition = texture(gWorldPos, fragTexcoords).rgb;
    vec3 rma = texture(gRoughnessMetalnessAo, fragTexcoords).rgb;
    vec3 emission = texture(gEmission, fragTexcoords).rgb;
    float depth  = texture(gDepth, fragTexcoords).r; // TODO, rerange this
    
    float roughness = rma.r;
    float metalness = rma.g;
    float ao = rma.b;
    
    vec3 N = normal;
    vec3 V = normalize(cameraPos - worldPosition);

    vec3 F0 = vec3(0.04); // common value for non-metallic objects
    F0 = mix(F0, albedo, metalness);

    vec3 Lo = vec3(0.0);

    // direct

    // directional light
    Lo += CalcDirectionalLight(directionalLight, N, V, albedo, roughness, metalness, F0);

    // Shadow calculation
    vec3 normalOffsetPos = worldPosition + N * 0.05;
    vec4 fragPosLightSpace = lightSpaceMatrix * vec4(normalOffsetPos, 1.0);
    float shadow = ShadowCalculation(fragPosLightSpace, N, directionalLight.direction);
    Lo *= (1 - shadow);

    // point
    int numPointLights = min(activePointLights, MAX_POINT_LIGHTS);
    for(int i = 0; i < numPointLights; i++)
	{
		Lo += CalcPointLight(pointLights[i], N, V, worldPosition, albedo, roughness, metalness, F0);
	}

    // spot
//    for(int i = 0; i < MAX_SPOT_LIGHTS; i++)
//    {
//        Lo += CalcSpotLight(spotLights[i], N, V, albedo, roughness, metalness, F0);
//    }
//

    // indirect (single scattering)
//    vec3 irradiance = texture(irradianceMap, normal).rgb;
//    vec3 ks = fresnelSchlickRoughness(max(dot(N, V), 0.0), F0, roughness);
//    vec3 kd = 1.0 - ks;
//    vec3 diffuse = kd * albedo * irradiance * (1 - metalness);
//
//    // IBL (image based lighting)
//    vec3 R = reflect(-V, N);
//    float mipLevel = roughness * 4.0;
//    vec3 prefilteredColor = textureLod(prefilterMap, R, mipLevel).rgb;
//    vec2 envBRDF = texture(brdfLUT, vec2(max(dot(N, V), 0.0), roughness)).rg;
//    vec3 specular = prefilteredColor * (ks * envBRDF.x + envBRDF.y);
//
//    vec3 indirectLight = (diffuse + specular) * ao;

    // indirect (multiple scattering)
    vec3 irradiance = texture(irradianceMap, normal).rgb;

    vec3 ks = fresnelSchlickRoughness(max(dot(N, V), 0.0), F0, roughness);
    vec3 R = reflect(-V, N);
    float mipLevel = roughness * 4.0;
    vec3 prefilteredColor = textureLod(prefilterMap, R, mipLevel).rgb;
    vec2 envBRDF = texture(brdfLUT, vec2(max(dot(N, V), 0.0), roughness)).rg;

    vec3 FssEss = ks * envBRDF.x + envBRDF.y;

    float Ems = (1.0 - (envBRDF.x + envBRDF.y));
    vec3 Favg = F0 + (1.0 - F0) / 21.0;
    vec3 FmsEms = Ems * FssEss * Favg / (1.0 - Favg * Ems);
    vec3 kd = albedo * (1.0 - FssEss - FmsEms) * (1.0 - metalness);
    vec3 indirectLight = (FssEss * prefilteredColor+ (FmsEms + kd) * irradiance) * ao;

    vec3 color = indirectLight + Lo;
    color = ToneMapACES(color);
    color = pow(vec3(color), vec3(1.0/2.2)); // gamma correction

    FragColor = vec4(vec3(color), 1.0);
}
