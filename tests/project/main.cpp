#ifndef integration_shader_SHADER_OUTPUT_FILE
#error "The shader output-file definition is missing"
#endif

constexpr const char* shader_output_file = integration_shader_SHADER_OUTPUT_FILE;

int main()
{
    return shader_output_file[0] == '\0';
}
