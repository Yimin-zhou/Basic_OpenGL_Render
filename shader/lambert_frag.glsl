#version 330 core

in vec3 FragPos;
in vec3 Normal;
in vec2 TexCoords;

out vec4 FragColor;

uniform vec4 diffuse;

void main() 
{
    FragColor = vec4(diffuse.rgb, 1.0f);
}
