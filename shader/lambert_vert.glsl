#version 430 core
layout (location = 0) in vec3 aPos; 
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec2 aTexCoord;

out vec3 FragPos;
out vec3 Normal;
out vec2 TexCoord;

void main() 
{
    gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);
    FragPos = aPos;
    Normal = aNormal;
    TexCoord = vec2(aTexCoord.x, aTexCoord.y);
}
