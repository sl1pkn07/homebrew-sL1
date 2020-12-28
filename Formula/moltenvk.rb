class Moltenvk < Formula
  desc "Implementation of the Vulkan 1.1 API, that runs on Apple's Metal API"
  homepage "https://github.com/KhronosGroup/MoltenVK"
  url "https://github.com/KhronosGroup/MoltenVK/archive/v1.1.1.tar.gz"
  sha256 "cd1712c571d4155f4143c435c8551a5cb8cbb311ad7fff03595322ab971682c0"

  depends_on "cereal" => :build
  depends_on "cmake" =>  :build
  depends_on "ninja" => :build
  depends_on "python" => :build
  depends_on xcode: ["11.7", :build]

  ver = "v#{version}"
  url_gh = "https://raw.githubusercontent.com/KhronosGroup"

  url_mltvk_er = "#{url_gh}/MoltenVk/#{ver}/ExternalRevisions"
  rev_vkh = Utils.safe_popen_read(
    "curl #{url_mltvk_er}/Vulkan-Headers_repo_revision",
  ).chomp
  rev_spvcr = Utils.safe_popen_read(
    "curl #{url_mltvk_er}/SPIRV-Cross_repo_revision",
  ).chomp
  rev_glsl = Utils.safe_popen_read(
    "curl #{url_mltvk_er}/glslang_repo_revision",
  ).chomp
  rev_vkt = Utils.safe_popen_read(
    "curl #{url_mltvk_er}/Vulkan-Tools_repo_revision",
  ).chomp

  url_glsl = "#{url_gh}/glslang/#{rev_glsl}"
  rev_glsl_spvh = Utils.safe_popen_read(
    "curl #{url_glsl}/known_good.json | grep -m2 'commit\"' | tail -n1 | cut -d '\"' -f4",
  ).chomp
  rev_glsl_spvt = Utils.safe_popen_read(
    "curl #{url_glsl}/known_good.json | grep -m2 'commit\"' | head -n1 | cut -d '\"' -f4",
  ).chomp

  resource "Vulkan-Headers" do
    url "https://github.com/KhronosGroup/Vulkan-Headers.git",
    revision: rev_vkh
  end
  resource "SPIRV-Cross" do
    url "https://github.com/KhronosGroup/SPIRV-Cross.git",
    revision: rev_spvcr
  end
  resource "glslang" do
    url "https://github.com/KhronosGroup/glslang.git",
    revision: rev_glsl
  end
  resource "Vulkan-Tools" do
    url "https://github.com/KhronosGroup/Vulkan-Tools.git",
    revision: rev_vkt
  end
  resource "glslang_SPIRV-Headers" do
    url "https://github.com/KhronosGroup/SPIRV-Headers.git",
    revision: rev_glsl_spvh
  end
  resource "glslang_SPIRV-Tools" do
    url "https://github.com/KhronosGroup/SPIRV-Tools.git",
    revision: rev_glsl_spvt
  end

  def install
    %w[Vulkan-Headers SPIRV-Cross glslang Vulkan-Tools].each do |r|
      resource(r).stage(Pathname.pwd/"External"/r)
    end

    resource("glslang_SPIRV-Tools").stage(
      Pathname.pwd/"External/glslang/External/spirv-tools",
    )
    resource("glslang_SPIRV-Headers").stage(
      Pathname.pwd/"External/glslang/External/spirv-tools/external/spirv-headers",
    )

    inreplace "Scripts/package_ext_libs_finish.sh",
              "make --quiet clean",
              ""

    inreplace "MoltenVK/MoltenVK.xcodeproj/project.pbxproj",
              '"\"$(SRCROOT)/../External/cereal/include\"",',
              "\"#{Formula["cereal"].opt_include}\","

    cd "External/glslang/External/spirv-tools" do
      # "Building SPIRV-Tools"
      args = std_cmake_args
      args << "-DPYTHON_EXECUTABLE=#{Formula["python"].opt_bin}/python3"
      args << "-DCMAKE_SKIP_RPATH=ON"

      mkdir "build" do
        system "cmake", "-G", "Ninja", "..", *args
        system "ninja"
      end
    end

    cd "External/glslang" do
      system "#{Formula["python"].opt_bin}/python3",
       "./build_info.py",
       ".",
       "-i", "./build_info.h.tmpl",
       "-o", "./build/include/glslang/build_info.h"
    end

    xcodebuild "-project", "ExternalDependencies.xcodeproj",
               "-scheme", "ExternalDependencies-macOS",
               "-derivedDataPath", "External/build",
               "SYMROOT=External/build",
               "OBJROOT=External/build",
               "build"

    xcodebuild "-create-xcframework",
               "-output", "External/build/Latest/SPIRVTools.xcframework",
               "-library", "External/build/Release/libSPIRVTools.a"
    xcodebuild "-create-xcframework",
               "-output", "External/build/Latest/SPIRVCross.xcframework",
               "-library", "External/build/Release/libSPIRVCross.a"
    xcodebuild "-create-xcframework",
               "-output", "External/build/Latest/glslang.xcframework",
               "-library", "External/build/Release/libglslang.a"

    xcodebuild "-project", "MoltenVKPackaging.xcodeproj",
               "-scheme", "MoltenVK Package (macOS only)",
               "-derivedDataPath", "#{buildpath}/build",
               "SYMROOT=#{buildpath}/build",
               "OBJROOT=#{buildpath}/build",
               "build"

    include.install Dir["Package/Release/MoltenVK/include/*"]
    lib.install "Package/Release/MoltenVK/dylib/macOS/libMoltenVK.dylib"
    frameworks.install "Package/Release/MoltenVK/MoltenVK.xcframework"
    (share/"vulkan/icd.d").install "MoltenVK/icd/MoltenVK_icd.json"

    include.install Dir["Package/Release/MoltenVKShaderConverter/include/*"]
    frameworks.install "Package/Release/MoltenVKShaderConverter/MoltenVKShaderConverter.xcframework"

    bin.install "Package/Release/MoltenVKShaderConverter/Tools/MoltenVKShaderConverter"
  end

  test do
    (testpath/"test.cpp").write <<~EOS
      #include <vulkan/vulkan.h>
      int main(void)
      {
          const char *extensionNames[] = { "VK_KHR_surface" };
          VkInstanceCreateInfo instanceCreateInfo = {
              VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, NULL,
              0, NULL,
              0, NULL,
              1, extensionNames,
          };
          VkInstance inst;
          vkCreateInstance(&instanceCreateInfo, NULL, &inst);
          return 0;
      }
    EOS
    system ENV.cc, "-o", "test", "test.cpp", "-L#{lib}", "-lMoltenVK"
    system "./test"
  end
end
