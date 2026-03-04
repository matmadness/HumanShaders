/*
MIT License
Copyright (c) 2025 MatMADNESS

Permission is hereby granted, free of charge, to use, copy, modify, and
distribute this software as permitted under the MIT License.

This Shader is part of the Human Shaders collection by MatMADNESS
and is built upon https://github.com/RustyRoboticsBV/GodotStandardLightShader
*/

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, sss_mode_skin;

global uniform int frame_index;

group_uniforms albedo;
uniform vec4 albedo : source_color = vec4(1.);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;

group_uniforms roughness;
uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform bool double_specularity = true;

uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;

group_uniforms metallic;
uniform float metallic : hint_range(0.0, 1.0, 0.01);
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_texture_channel;

group_uniforms normal;
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_strength : hint_range(-16.0, 16.0) = 1.0;

group_uniforms micro_detail;
uniform bool use_micro_detail = false;
uniform float micro_detail_scale : hint_range(0.0, 200.0) = 25.0;
uniform float micro_normal_strength : hint_range(-1.0, 1.0) = 0.3;
uniform float micro_ao_strength : hint_range(-1.0, 1.0) = 0.4;
uniform sampler2D texture_micro_detail : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
//uniform float soften_normal : hint_range(0.0, 1.0);

group_uniforms ambient_occlusion;
uniform bool use_ambient_occlusion = false;
uniform sampler2D ambient_occlusion_texture : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform float ao_strength : hint_range(0.0, 2.0) = 0.5;
uniform float ao_block_light : hint_range(0.0, 2.0) = 0.5;

group_uniforms subsurface_scattering;
uniform bool use_subsurface_scattering = true;
uniform bool use_noise = true;
uniform float subsurface_scattering_strength : hint_range(0.0, 1.0, 0.01) = 0.4;
uniform float skin_smoothness : hint_range(0.0, 10.0) = 5.0;
uniform float skin_fallof_smoothness : hint_range(0.7, 2.0, 0.01) = 1.0;
uniform bool tinted_shadow_penumbra = false;
uniform bool old_lightwarp_fallof = false;
uniform sampler2D lightwarp : source_color, filter_linear, repeat_disable;
uniform sampler2D texture_sss_noise : filter_linear, repeat_enable, source_color;


group_uniforms translucency;
uniform bool translucency = false;
uniform float translucency_strength : hint_range(0.0, 2.0, 0.01) = 0.75;
uniform sampler2D texture_translucency : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_translucency_color : source_color, filter_linear, repeat_disable;

group_uniforms u_v;
uniform vec3 uv1_scale = vec3(1.);
uniform vec3 uv1_offset = vec3(0.);
uniform vec3 uv2_scale = vec3(1.);
uniform vec3 uv2_offset = vec3(0.);

varying mat3 TBN;
varying vec4 micro_detail;
varying vec3 final_albedo;
varying float final_metallic;
varying float ao;
varying float linear_depth;
varying float smooth_depth;
varying float sss_tex;
varying vec3 RAW_NORMAL;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	// Detail UV Layer: UV2
	UV2 = UV2 * uv2_scale.xy + uv2_offset.xy;
}

vec3 normal_blending(vec3 b, vec3 d) {
	return vec3(b.xy + d.xy - 0.5, b.z);
}

vec3 overlay(vec3 base, vec3 blend) {
	vec3 limit = step(0.5, base);
	return mix(2.0 * base * blend, 1.0 - 2.0 * (1.0 - base) * (1.0 - blend), limit);
}

vec3 custom_normal(vec3 normal_map) {
	normal_map = mix(vec3(0.5,0.5,1.0), normal_map, normal_strength);
	vec3 normal_tangent = vec3(
		normal_map.r * 2.0 - 1.0,  // X-axis (unchanged)
		(1.0 - normal_map.g) * 2.0 - 1.0,  // Y-axis (inverted)
		1   // Z-axis (solid blue)
		);
	return normalize(TBN * normal_tangent);
}

float ign_noise(vec2 uv) {
	return fract(52.9829189 * fract(dot(uv, vec2(0.06711056, 0.00583715))));
}

float halton(int index, int base) {
	float f = 1.0;
	float result = 0.0;
	
	while (index > 0) {
		f /= float(base);
		result += f * float(index % base);
		index = index / base;
	}
	
	return result;
}

vec2 halton2(int frame) {
	return vec2(halton(frame, 2), halton(frame, 4));
}

void fragment() {
	vec2 base_uv = UV;
	TBN = mat3(TANGENT, -BINORMAL, NORMAL);
	RAW_NORMAL = NORMAL;

	//Raw depth value:
	float depth_raw = FRAGCOORD.z;

	//Convert to linear:
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;

	// reverse
	linear_depth = clamp(1. + (view.z / 1.0), 0., 1.);
	smooth_depth = smoothstep(0.0, 0.6, linear_depth);

	sss_tex = texture(texture_translucency, base_uv).b;

	micro_detail = texture(texture_micro_detail, base_uv * micro_detail_scale);
	ao = texture(texture_normal, base_uv).b;
	ao *= texture(ambient_occlusion_texture, base_uv).r;

	float micro_overlay = mix(0.5, micro_detail.b, micro_ao_strength * 2.);
	vec4 albedo_tex = texture(texture_albedo, base_uv);
	if (use_micro_detail){
		albedo_tex = vec4(overlay(albedo_tex.rgb, vec3(micro_overlay)), albedo_tex.w);
	}

	final_albedo = albedo.rgb * albedo_tex.rgb;

	float metallic_tex = dot(texture(texture_metallic, base_uv), metallic_texture_channel);
	final_metallic = metallic_tex * metallic;
	ALBEDO = final_albedo * (1.0 - final_metallic);


	//METALLIC = metallic_tex * metallic;

	//float spec = max(dot(NORMAL, LIGHT_VERTEX * LIGHT_VERTEX), 0.0);

	//ALBEDO = vec3(1.);
	
	//SPECULAR = clamp(specular, 0.,1.);
	if (use_ambient_occlusion){
		SPECULAR *= ao;
	}
	
	vec4 roughness_texture_channel = vec4(0.0, 1.0, 0.0, 0.0);
	float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);
	ROUGHNESS = clamp(roughness_tex * roughness, 0.,1.);

	// Normal Map: Enabled
	vec3 micro_normal = mix(vec3(.5,.5,1.), vec3(micro_detail.xy, 1.), micro_normal_strength);

	//Normal Map (For Specular):
	vec3 normal_final = texture(texture_normal, base_uv).rgb;
	normal_final = normal_blending(normal_final, micro_normal);
	NORMAL_MAP = normal_final;
	NORMAL_MAP_DEPTH = normal_strength;

	// Ambient Occlusion
	if (use_ambient_occlusion){
		AO = ao * ao_strength + (1.-ao_strength);// * smoothstep(0.,1., micro_detail.z * 1.6);
		AO_LIGHT_AFFECT = 0.0;
	}

	// Subsurface Scattering: Enabled
	if (use_subsurface_scattering){
		if (smooth_depth > 0.){
			float sss_strength_value = subsurface_scattering_strength * 2.0;
			if (translucency){
				sss_strength_value += (sss_tex * 2.);
			}
			if (use_noise){
				vec2 pixel_uv = floor(FRAGCOORD.xy);
				vec2 frame_jitter = halton2(frame_index % 1024);
				float noise = ign_noise(pixel_uv + frame_jitter * 1024.0);
				//noise = ign_noise(pixel_uv);
				sss_strength_value *= noise * 2.0;
			}
			SSS_STRENGTH = sss_strength_value * texture(ambient_occlusion_texture, base_uv).r * smooth_depth;
		}
	}
}

float DistributionGGX(float cos_theta_m, float alpha){
	float alpha2 = alpha * alpha;
	float d = 1.0 + (alpha2 - 1.0) * cos_theta_m * cos_theta_m;
	return alpha2 / (PI * d * d);
}

float GeometryGGX(float NdotL, float NdotV, float alpha){
	return 0.5 / mix(2.0 * NdotL * NdotV, NdotL + NdotV, alpha);
}

vec3 SchlickBaseReflectivity(){
	float dielectric = 0.04 * specular * specular;
	return mix(vec3(dielectric), final_albedo, vec3(final_metallic));
}

float SchlickFresnel(float u){
	float m = 1.0 - u;
	float m2 = m * m;
	return m2 * m2 * m;
}

float DiffuseBurley(float NdotL, float NdotV, float LdotH, float linear_roughness) {
    // Burley 2012, "Physically-Based Shading at Disney"
	float f90 = 2.0 * linear_roughness * LdotH * LdotH - 0.5;
	float l_scatter = 1.0 + f90 * SchlickFresnel(NdotL);
	float v_scatter = 1.0 + f90 * SchlickFresnel(NdotV);
	return v_scatter * l_scatter * NdotL * 0.318309;
}

float DiffuseBurleySkin(sampler2D normal_map, vec2 uv, float NdotL, float NdotV, float LdotH, float linear_roughness) {
    // Burley 2012, "Physically-Based Shading at Disney"
	//Calculate custom diffuse normal (dn):
	float s = skin_smoothness;
	vec3 dn_r = custom_normal(textureLod(texture_normal, uv, (1.*s)).rgb);
	vec3 dn_g = custom_normal(textureLod(texture_normal, uv, (0.8*s)).rgb);
	vec3 dn_b = custom_normal(textureLod(texture_normal, uv, (0.7*s)).rgb);
		
	//Include micro normals in the mix:
	vec3 m_normal = texture(texture_micro_detail, uv * micro_detail_scale).rgb;
	m_normal = mix(vec3(.5,.5,1.), vec3(m_normal.xy, 1.), micro_normal_strength);
	
	dn_g = normal_blending(dn_g, m_normal);
	dn_b = normal_blending(dn_b, m_normal);
	////
	
	float f90 = 2.0 * linear_roughness * LdotH * LdotH - 0.5;
	float l_scatter = 1.0 + f90 * SchlickFresnel(NdotL);
	float v_scatter = 1.0 + f90 * SchlickFresnel(NdotV);
	return v_scatter * l_scatter * NdotL * (1.0 / PI);
}

/**/
void light()
{
	// Calculate some vectors.
	vec3 lightColor = LIGHT_COLOR / PI;

	vec3 half = normalize(VIEW + LIGHT);

	float NdotL = max(dot(NORMAL, LIGHT), 0.0);
	float NdotV = max(dot(NORMAL, VIEW), 0.0);
	float NdotH = max(dot(NORMAL, half), 0.0);
	float LdotH = max(dot(LIGHT, half), 0.0);

	// Diffuse light (Lambert):
	//DIFFUSE_LIGHT += clamp(dot(mix(DIFFUSE_NORMAL, NORMAL, 0.3), LIGHT),0.,1.) * ATTENUATION * lightColor;

	//Custom wrapped diffuse:
	float wrap = 0.5;
	vec3 diff_light;
	float normal_depth = max((1.5-linear_depth), 1.);
	//normal_depth = 1.;

	if (!old_lightwarp_fallof){ //Better SSS aproximation:

		//Calculate custom diffuse normal (dn):
		float s = skin_smoothness;
		vec3 dn_r = custom_normal(textureLod(texture_normal, UV, (1.*s) * normal_depth).rgb);
		vec3 dn_g = custom_normal(textureLod(texture_normal, UV, (0.8*s) * normal_depth).rgb);
		vec3 dn_b = custom_normal(textureLod(texture_normal, UV, (0.7*s) * normal_depth).rgb);
		
		//Include micro normals in the mix:
		vec3 m_normal = texture(texture_micro_detail, UV * micro_detail_scale).rgb;
		m_normal = mix(vec3(.5,.5,1.), vec3(m_normal.xy, 1.), micro_normal_strength);
		
		dn_g = normal_blending(dn_g, m_normal);
		dn_b = normal_blending(dn_b, m_normal);
		////
		
		float spec_smoothness = min(SPECULAR_AMOUNT * 0.75 + 0.25, 1.0);
		float sf = skin_fallof_smoothness / (spec_smoothness);
		
		float wrapped_r = smoothstep(0.4 /sf, 1.2 *sf, dot(dn_r, LIGHT) * wrap + (1.0-wrap));
		float wrapped_g = smoothstep(0.425 /sf, 1.2 *sf, dot(dn_g, LIGHT) * wrap + (1.0-wrap));
		float wrapped_b = smoothstep(0.44 /sf, 1.2 *sf, dot(dn_b, LIGHT) * wrap + (1.0-wrap));
		vec3 wrapped_rgb = vec3(wrapped_r, wrapped_g, wrapped_b) * mix(sf, sf * sf, 0.5);
		if (use_ambient_occlusion){
			wrapped_rgb *= (ao * ao_block_light + (1.-ao_block_light));
		}
		
		float RNdotL = clamp(dot(RAW_NORMAL, LIGHT), 0.0, 1.0);
		RNdotL = mix (RNdotL, RNdotL * 0.5 + 0.5, clamp(sf - 1.0, 0.0, 1.0));
		float RNdotV = clamp(dot(RAW_NORMAL, VIEW), 0.0, 1.0);
		RNdotV = mix (RNdotV, RNdotV * 0.5 + 0.5, clamp(sf - 1.0, 0.0, 1.0));
		
		float f90 = 3.0 * roughness * LdotH * LdotH - 0.5;
		float l_scatter = 1.0 + f90 * SchlickFresnel(RNdotL);
		float v_scatter = 1.0 + f90 * SchlickFresnel(RNdotV) * 3.0;
		float combined = v_scatter * l_scatter;

		diff_light = wrapped_rgb * combined;
	}
	else{ //Lightwarp technique:
		vec3 diff_normal_map = mix(
			textureLod(texture_normal, UV, 6. * normal_depth).rgb,
			textureLod(texture_normal, UV, 3. * normal_depth).rgb,
			.2);
		vec3 diff_normal = custom_normal(diff_normal_map);

		float wrapped = pow(dot(diff_normal, LIGHT) * wrap + (1.0-wrap), 2.0);
		vec3 lw = texture(lightwarp, vec2(wrapped, 0.0)).rgb;
		if (use_ambient_occlusion){
			lw = texture(lightwarp, vec2(wrapped * (ao * ao_block_light + (1.-ao_block_light)), 0.0)).rgb;
		}
		diff_light = lw;
	}
	
	//diff_light += vec3(DiffuseBurleySkin(texture_normal, UV, NdotL, NdotV, LdotH, ROUGHNESS));
	//diff_light += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * (lightColor / (TAU* 2.0));
	
	//Tint shadow penumbra:
	vec3 att = overlay(min(vec3(ATTENUATION), 1.), vec3(1.2,.8,.6)) * max(ATTENUATION, 0.5);
	if (tinted_shadow_penumbra){att = att;} else{att = vec3(ATTENUATION);}

	DIFFUSE_LIGHT += diff_light * att * lightColor;

	if (translucency){
		float translucency_dot = dot(VIEW,-(LIGHT + NORMAL * .4));
		vec2 t_col_coord = vec2(sss_tex * translucency_dot * translucency_strength, 0.0);
		vec3 t_color = texture(texture_translucency_color, t_col_coord).rgb;
		vec3 translucent = max(translucency_dot * t_color, 0.0) * lightColor;
		//translucency *= max(translucency_strength, 1.);

		DIFFUSE_LIGHT += translucent;
	}
	
	// Specular light (Schlick-GGX).
	vec3 f0 = SchlickBaseReflectivity();
	float LdotH5 = SchlickFresnel(LdotH);
	float f90 = clamp(50.0 * f0.g, 0.0, 1.0);
	vec3 F = f0 + (f90 - f0) * LdotH5;
	
	float ggxAlpha = ROUGHNESS * ROUGHNESS;
	float D = DistributionGGX(NdotH, ggxAlpha);
	float G = GeometryGGX(NdotL, NdotV, ggxAlpha);
	
	vec3 specularBRDF;
	
	if (!double_specularity) {
		specularBRDF = max(NdotL * D * G * F, 0.0);
	}
	else {
		float D = DistributionGGX(NdotH, ggxAlpha + .15);
		specularBRDF = max(NdotL * D * G * F, 0.0) * 2.0;
		
		float D2 = DistributionGGX(NdotH, ggxAlpha * 0.5);
		vec3 specularBRDF2 = max(NdotL * D2 * G * F, 0.0);
		
		specularBRDF = (specularBRDF + specularBRDF2) / 2.0;
	}
	SPECULAR_LIGHT += specularBRDF * LIGHT_COLOR * ATTENUATION * (SPECULAR_AMOUNT + 0.1);
	
	if (use_ambient_occlusion){
		SPECULAR_LIGHT *= ao * ao_block_light + (1.-ao_block_light);
	}
	
	//SPECULAR_LIGHT = vec3(0.0);
}
