class Moltenvk < Formula
  desc "Implementation of the Vulkan 1.0 API, that runs on Apple's Metal API"
  homepage "https://github.com/KhronosGroup/MoltenVK"
  url "https://github.com/KhronosGroup/MoltenVK.git", :tag => "v1.0.34"
  head "https://github.com/KhronosGroup/MoltenVK.git"

  depends_on "cereal" => :build
  depends_on "cmake" => :build
  depends_on "ninja" => :build
  depends_on "python" => :build
  depends_on :xcode => :build

  resource "Vulkan-Headers" do
    revi = Utils.popen_read("cat #{HOMEBREW_CACHE}/moltenvk--git/ExternalRevisions/Vulkan-Headers_repo_revision").chomp
    url "https://github.com/KhronosGroup/Vulkan-Headers.git", :revision => revi
  end
  resource "Vulkan-Portability" do
    revi = Utils.popen_read("cat #{HOMEBREW_CACHE}/moltenvk--git/ExternalRevisions/Vulkan-Portability_repo_revision").chomp
    url "https://github.com/KhronosGroup/Vulkan-Portability.git", :revision => revi
  end
  resource "SPIRV-Cross" do
    revi = Utils.popen_read("cat #{HOMEBREW_CACHE}/moltenvk--git/ExternalRevisions/SPIRV-Cross_repo_revision").chomp
    url "https://github.com/KhronosGroup/SPIRV-Cross.git", :revision => revi
  end
  resource "glslang" do
    revi = Utils.popen_read("cat #{HOMEBREW_CACHE}/moltenvk--git/ExternalRevisions/glslang_repo_revision").chomp
    url "https://github.com/KhronosGroup/glslang.git", :revision => revi
  end
  resource "Vulkan-Tools" do
    revi = Utils.popen_read("cat #{HOMEBREW_CACHE}/moltenvk--git/ExternalRevisions/Vulkan-Tools_repo_revision").chomp
    url "https://github.com/KhronosGroup/Vulkan-Tools.git", :revision => revi
  end
  resource "glslang_SPIRV-Headers" do
    revi = Utils.popen_read("cat #{HOMEBREW_CACHE}/moltenvk--glslang--git/known_good.json | grep -m2 'commit\"' | tail -n1 | cut -d '\"' -f4").chomp
    url "https://github.com/KhronosGroup/SPIRV-Headers.git", :revision => revi
  end
  resource "glslang_SPIRV-Tools" do
    revi = Utils.popen_read("cat #{HOMEBREW_CACHE}/moltenvk--glslang--git/known_good.json | grep -m2 'commit\"' | head -n1 | cut -d '\"' -f4").chomp
    url "https://github.com/KhronosGroup/SPIRV-Tools.git", :revision => revi
  end

  def install
    ["Vulkan-Headers", "Vulkan-Portability", "SPIRV-Cross", "glslang", "Vulkan-Tools"].each do |r|
      resource(r).stage(Pathname.pwd/"External"/r)
    end

    resource("glslang_SPIRV-Tools").stage(Pathname.pwd/"External/glslang/External/spirv-tools")
    resource("glslang_SPIRV-Headers").stage(Pathname.pwd/"External/glslang/External/spirv-tools/external/spirv-headers")

    inreplace "Scripts/package_ext_libs.sh",
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

    xcodebuild "-project",
      "ExternalDependencies.xcodeproj",
      "-scheme", "ExternalDependencies-macOS",
      "-derivedDataPath", "External/build",
      "SYMROOT=External/build",
      "OBJROOT=External/build",
      "build"

    xcodebuild "-project",
      "MoltenVKPackaging.xcodeproj",
      "-scheme", "MoltenVK Package (macOS only)",
      "-derivedDataPath", "#{buildpath}/build",
      "SYMROOT=#{buildpath}/build",
      "OBJROOT=#{buildpath}/build",
      "build"

    include.install Dir["Package/Release/MoltenVK/include/*"]
    lib.install Dir["Package/Release/MoltenVK/macOS/dynamic/*"]
    lib.install "Package/Release/MoltenVK/macOS/static/libMoltenVK.a"
    frameworks.install "Package/Release/MoltenVK/macOS/framework/MoltenVK.framework"

    include.install Dir["Package/Release/MoltenVKShaderConverter/include/*"]
    lib.install "Package/Release/MoltenVKShaderConverter/MoltenVKGLSLToSPIRVConverter/macOS/dynamic/libMoltenVKGLSLToSPIRVConverter.dylib"
    lib.install "Package/Release/MoltenVKShaderConverter/MoltenVKGLSLToSPIRVConverter/macOS/static/libMoltenVKGLSLToSPIRVConverter.a"
    frameworks.install "Package/Release/MoltenVKShaderConverter/MoltenVKGLSLToSPIRVConverter/macOS/framework/MoltenVKGLSLToSPIRVConverter.framework"

    lib.install "Package/Release/MoltenVKShaderConverter/MoltenVKSPIRVToMSLConverter/macOS/dynamic/libMoltenVKSPIRVToMSLConverter.dylib"
    lib.install "Package/Release/MoltenVKShaderConverter/MoltenVKSPIRVToMSLConverter/macOS/static/libMoltenVKSPIRVToMSLConverter.a"
    frameworks.install "Package/Release/MoltenVKShaderConverter/MoltenVKSPIRVToMSLConverter/macOS/framework/MoltenVKSPIRVToMSLConverter.framework"

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
