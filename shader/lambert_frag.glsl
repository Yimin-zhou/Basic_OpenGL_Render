#version 330 core

in vec3 FragPos;
in vec3 Normal;
in vec2 TexCoords;

out vec4 FragColor;

uniform vec4 color;

void main() 
{
    FragColor = vec4(color.rgb, 1.0f);
}