package vktest

import "core:fmt"
import "core:os"
import "core:math"
import "core:math/linalg"
import "core:log"
import "core:bytes"
import "core:strings"
import "core:c"
import "core:time"
import "core:mem"

import "base:runtime"

import "vendor:glfw"
import vk "vendor:vulkan"
import stbi "vendor:stb/image"
import "vendor:cgltf"

ENABLE_VALIDATION_LAYERS :: false

NULL_HANDLE :: 0
MAX_FRAMES_IN_FLIGHT :: 2

winWidth  : c.int = 1600
winHeight : c.int = 900

validationLayers: []cstring:
{
	"VK_LAYER_KHRONOS_validation"		
}

deviceExtensions := []cstring {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME
}
 
Application :: struct
{
	window:              glfw.WindowHandle,
	instance:            vk.Instance,
	extensions:          []vk.ExtensionProperties,
	debugMessenger:      vk.DebugUtilsMessengerEXT,
	physicalDevice:      vk.PhysicalDevice,
	device:              vk.Device,
	graphicsQueue:       vk.Queue,
	presentQueue:        vk.Queue,
	surface:             vk.SurfaceKHR,
	swapchain:           vk.SwapchainKHR,
	swapImages:          [dynamic]vk.Image,
	swapImageFormat:     vk.Format,
	swapImageViews:      [dynamic]vk.ImageView,
	swapFramebuffers:    [dynamic]vk.Framebuffer,
	swapExtent:          vk.Extent2D,
	descriptorPool:      vk.DescriptorPool,
	descriptorSetLayout: vk.DescriptorSetLayout,
	descriptorSets:      [dynamic]vk.DescriptorSet,
	pipelineLayout:      vk.PipelineLayout,
	renderPass:          vk.RenderPass,
	graphicsPipeline:    vk.Pipeline,
	commandPool:         vk.CommandPool,
	commandBuffers:      [dynamic]vk.CommandBuffer,
	vertexBuffer:        vk.Buffer,
	vertexBufferMemory:  vk.DeviceMemory,
	indexBuffer:         vk.Buffer,
	indexBufferMemory:   vk.DeviceMemory,
	mipLevels:           u32,
	textureImage:        vk.Image,
	textureMemory:       vk.DeviceMemory,
	textureImageView:    vk.ImageView,
	textureSampler:      vk.Sampler,
	depthImage:          vk.Image,
	depthImageMemory:    vk.DeviceMemory,
	depthImageView:      vk.ImageView,

	vertices: []Vertex,
	indices:  []u16,
	
	uniformBuffers:       [dynamic]vk.Buffer,
	uniformBuffersMemory: [dynamic]vk.DeviceMemory,
	uniformBuffersMapped: [dynamic]rawptr,
	
	imgAvailableSemaphores:   [dynamic]vk.Semaphore,
	renderFinishedSemaphores: [dynamic]vk.Semaphore,
	inFlightFences:           [dynamic]vk.Fence,
	
	wasFramebufferResized: bool,
	currentFrame:          u32,
	lastFrameRenderTime:   f64,
	dt:                    f32,
}
app: Application


QueueFamilyIndices :: struct
{
	graphicsFamily: Maybe(u32),
	presentFamily:  Maybe(u32),
}

SwapchainSupportDetails :: struct
{
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:      [dynamic]vk.SurfaceFormatKHR,
	presentModes: [dynamic]vk.PresentModeKHR,
}

Mat4 :: linalg.Matrix4x4f32
UniformBufferObject :: struct
{
	model: Mat4,
	view:  Mat4,
	proj:  Mat4,
}

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32

Vertex :: struct
{
	pos:      Vec3,
	col:      Vec3,
	texCoord: Vec2,
}

init_window :: proc()
{
	initOk := glfw.Init()
	if !initOk
	{
		desc, err := glfw.GetError()
		fmt.panicf("Could not init glfw: ", desc, err)
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE,  glfw.TRUE)
	app.window = glfw.CreateWindow(winWidth, winHeight, "VKTEST", nil, nil)
	glfw.MakeContextCurrent(app.window)
	
	glfw.SetKeyCallback(app.window, key_callback)
	glfw.SetFramebufferSizeCallback(app.window, framebuffer_size_callback)
}

framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: c.int)
{
	app.wasFramebufferResized = true
}

init_vulkan :: proc()
{
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	
	create_instance()
	vk.load_proc_addresses_instance(app.instance)
	
	setup_debug_messenger()
	create_surface()
	pick_physical_device()
	create_logical_device()
	vk.load_proc_addresses_device(app.device)

	create_swapchain()
	create_image_views()
	create_render_pass()
	create_descriptor_set_layout()
	create_graphics_pipeline()
	create_command_pool()
	create_depth_resources()
	create_framebuffers()
	create_texture_image()
	create_texture_image_view()
	create_texture_sampler()
	load_model("res/models/spitter.gltf")
	create_vertex_buffer()
	create_index_buffer()
	create_uniform_buffers()
	create_descriptor_pool()
	create_descriptor_sets()
	create_command_buffers()
	create_sync_objects()
}

cleanup :: proc()
{
	cleanup_swapchain()

	vk.DestroySampler(app.device, app.textureSampler, nil)
	vk.DestroyImageView(app.device, app.textureImageView, nil)
	vk.DestroyImage(app.device, app.textureImage, nil)
	vk.FreeMemory(app.device, app.textureMemory, nil)
	
	vk.DestroyImageView(app.device, app.depthImageView, nil)
	vk.DestroyImage(app.device, app.depthImage, nil)
	vk.FreeMemory(app.device, app.depthImageMemory, nil)

	for i in 0..<MAX_FRAMES_IN_FLIGHT
	{
		vk.DestroyBuffer(app.device, app.uniformBuffers[i], nil)
		vk.FreeMemory(app.device, app.uniformBuffersMemory[i], nil)

	}
	
	vk.DestroyDescriptorPool(app.device, app.descriptorPool, nil)
	vk.DestroyDescriptorSetLayout(app.device, app.descriptorSetLayout, nil)

	vk.DestroyBuffer(app.device, app.vertexBuffer, nil)
	vk.FreeMemory(app.device, app.vertexBufferMemory, nil)
	
	vk.DestroyBuffer(app.device, app.indexBuffer, nil)
	vk.FreeMemory(app.device, app.indexBufferMemory, nil)
	
	vk.DestroyPipeline(app.device, app.graphicsPipeline, nil)
	vk.DestroyPipelineLayout(app.device, app.pipelineLayout, nil)
	vk.DestroyRenderPass(app.device, app.renderPass, nil)
	
	for i in 0..<MAX_FRAMES_IN_FLIGHT
	{
		vk.DestroySemaphore(app.device, app.imgAvailableSemaphores[i], nil)
		vk.DestroySemaphore(app.device, app.renderFinishedSemaphores[i], nil)
		vk.DestroyFence(app.device, app.inFlightFences[i], nil)
	}
	
	vk.DestroyCommandPool(app.device, app.commandPool, nil)
	vk.DestroyDevice(app.device, nil)
	
	if ENABLE_VALIDATION_LAYERS
	{
		vk.DestroyDebugUtilsMessengerEXT(app.instance, app.debugMessenger, nil)
	}
	
	vk.DestroySurfaceKHR(app.instance, app.surface, nil)
	vk.DestroyInstance(app.instance, nil)

	glfw.DestroyWindow(app.window)
	glfw.Terminate()
}

main_loop :: proc()
{
	init_game()
	
	for !glfw.WindowShouldClose(app.window)
	{
		glfw.PollEvents()
		update_input()
		update_fps()
		
		// Update deltatime
		curTime := glfw.GetTime()
		app.dt = f32(curTime - app.lastFrameRenderTime)
		app.lastFrameRenderTime = curTime
		
		move_camera()
		reset_input()
		
		draw_frame()
	}

	vk.DeviceWaitIdle(app.device)
}

get_binding_description :: proc() -> vk.VertexInputBindingDescription
{
	desc: vk.VertexInputBindingDescription
	desc.binding = 0
	desc.stride = size_of(Vertex)
	desc.inputRate = .VERTEX
	return desc
}

get_attribute_description :: proc() -> []vk.VertexInputAttributeDescription
{
	desc := make([]vk.VertexInputAttributeDescription, 3)
	
	desc[0].binding = 0
	desc[0].location = 0
	desc[0].format = .R32G32B32_SFLOAT
	desc[0].offset = u32(offset_of_by_string(Vertex, "pos"))

	desc[1].binding = 0
	desc[1].location = 1
	desc[1].format = .R32G32B32_SFLOAT
	desc[1].offset = u32(offset_of_by_string(Vertex, "col"))

	desc[2].binding = 0
	desc[2].location = 2
	desc[2].format = .R32G32_SFLOAT
	desc[2].offset = u32(offset_of_by_string(Vertex, "texCoord"))
	
	return desc
}

draw_frame :: proc()
{
	vk.WaitForFences(app.device, 1, &app.inFlightFences[app.currentFrame], true, max(u64))

	update_uniform_buffer(app.currentFrame)

	imgIndex: u32
	result := vk.AcquireNextImageKHR(app.device, app.swapchain, max(u64), app.imgAvailableSemaphores[app.currentFrame], NULL_HANDLE, &imgIndex)
	if result == .ERROR_OUT_OF_DATE_KHR
	{
		recreate_swapchain()
		return
	}
	else if result != .SUCCESS && result != .SUBOPTIMAL_KHR
	{
		fmt.panicf("Failed to acquire swapchain image")
	}
	
	vk.ResetFences(app.device, 1, &app.inFlightFences[app.currentFrame])

	vk.ResetCommandBuffer(app.commandBuffers[app.currentFrame], nil) // KENTIES
	record_command_buffer(app.commandBuffers[app.currentFrame], imgIndex)
	

	submitInfo: vk.SubmitInfo
	submitInfo.sType = .SUBMIT_INFO
		
	waitSemas:   []vk.Semaphore = {app.imgAvailableSemaphores[app.currentFrame]}
	waitStages: vk.PipelineStageFlags = {.COLOR_ATTACHMENT_OUTPUT}
	submitInfo.waitSemaphoreCount = 1
	submitInfo.pWaitSemaphores = raw_data(waitSemas)
	submitInfo.pWaitDstStageMask = &waitStages
	
	submitInfo.commandBufferCount = 1
	submitInfo.pCommandBuffers = &app.commandBuffers[app.currentFrame]
	
	signalSemas: []vk.Semaphore = {app.renderFinishedSemaphores[app.currentFrame]}
	submitInfo.signalSemaphoreCount = 1
	submitInfo.pSignalSemaphores = raw_data(signalSemas)

	if vk.QueueSubmit(app.graphicsQueue, 1, &submitInfo, app.inFlightFences[app.currentFrame]) != .SUCCESS
	{
		fmt.panicf("Failed to submit draw command buffer")
	}

	presentInfo: vk.PresentInfoKHR
	presentInfo.sType = .PRESENT_INFO_KHR
	presentInfo.waitSemaphoreCount = 1
	presentInfo.pWaitSemaphores = raw_data(signalSemas)

	swapchains: []vk.SwapchainKHR = {app.swapchain}
	presentInfo.swapchainCount = 1
	presentInfo.pSwapchains = raw_data(swapchains)
	presentInfo.pImageIndices = &imgIndex

	result = vk.QueuePresentKHR(app.presentQueue, &presentInfo)
	if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR || app.wasFramebufferResized
	{
		app.wasFramebufferResized = false
		recreate_swapchain()
	}
	else if result != .SUCCESS
	{
		fmt.panicf("Failed to acquire swapchain image")
	}

	app.currentFrame = (app.currentFrame + 1) % MAX_FRAMES_IN_FLIGHT
}

create_instance :: proc()
{
	if ENABLE_VALIDATION_LAYERS && !check_validation_layer_support()
	{
		fmt.panicf("Validation layers requested, but not available")
	}
	
	appInfo: vk.ApplicationInfo
	appInfo.sType = .APPLICATION_INFO
	appInfo.pApplicationName = "VkTest"
	appInfo.pEngineName = "No Engine"
	appInfo.applicationVersion = vk.MAKE_VERSION(1, 0, 0)
	appInfo.engineVersion      = vk.MAKE_VERSION(1, 0, 0)
	appInfo.apiVersion         = vk.MAKE_VERSION(1, 0, 0)

	createInfo: vk.InstanceCreateInfo
	createInfo.sType = .INSTANCE_CREATE_INFO
	createInfo.pApplicationInfo = &appInfo

	exts := get_required_extensions()
	createInfo.enabledExtensionCount = u32(len(exts))
	createInfo.ppEnabledExtensionNames = raw_data(exts)

	debugCreateInfo: vk.DebugUtilsMessengerCreateInfoEXT
	if ENABLE_VALIDATION_LAYERS
	{
		createInfo.enabledLayerCount = u32(len(validationLayers))
		createInfo.ppEnabledLayerNames = raw_data(validationLayers)

		populate_debug_messenger_create_info(&debugCreateInfo)
		createInfo.pNext = rawptr(&debugCreateInfo) // FIX maybe wrong 
	}
	else
	{
		createInfo.enabledLayerCount = 0
		createInfo.pNext = nil
	}

	result := vk.CreateInstance(&createInfo, nil, &app.instance)
	if result != .SUCCESS
	{
		fmt.panicf("Could not create vulkan instance")
	}
	
}

pick_physical_device :: proc()
{
	count: u32
	vk.EnumeratePhysicalDevices(app.instance, &count, nil)
	if count == 0
	{
		fmt.panicf("Could not find GPUs with vulkan support")
	}
	
	devices := make([]vk.PhysicalDevice, count)
	vk.EnumeratePhysicalDevices(app.instance, &count, raw_data(devices))

	suitableDevices: [dynamic]vk.PhysicalDevice

	for dev in devices
	{
		if is_device_suitable(dev)
		{
			app.physicalDevice = dev
			append(&suitableDevices, dev)
		}
	}

	// Pick best physical device
	chosenDevice: vk.PhysicalDevice
	for dev in suitableDevices
	{
		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(dev, &props)

		if props.deviceType == .DISCRETE_GPU
		{
			chosenDevice = dev
			fmt.printfln("Chosen physical device: %s", props.deviceName)
			break
		}

	}

	if chosenDevice == nil
	{
		fmt.panicf("Failed to find suitable GPU")
	}
	else
	{
		app.physicalDevice = chosenDevice
	}
}

create_logical_device :: proc()
{
	indices := find_queue_families(app.physicalDevice)

	queueCreateInfos: [dynamic]vk.DeviceQueueCreateInfo
	uniqueFamilies:   [dynamic]u32
	
	append(&uniqueFamilies, indices.graphicsFamily.(u32))
	if indices.graphicsFamily.(u32) != indices.graphicsFamily.(u32)
	{
		append(&uniqueFamilies, indices.presentFamily.(u32))
	}
	
	priority: f32 = 1
	for fam in uniqueFamilies
	{
		queueCreateInfo: vk.DeviceQueueCreateInfo
		queueCreateInfo.sType = .DEVICE_QUEUE_CREATE_INFO
		queueCreateInfo.queueFamilyIndex = fam
		queueCreateInfo.queueCount = 1
		queueCreateInfo.pQueuePriorities = &priority
		append(&queueCreateInfos, queueCreateInfo)
	}

	features: vk.PhysicalDeviceFeatures
	features.samplerAnisotropy = true

	createInfo: vk.DeviceCreateInfo
	createInfo.sType = .DEVICE_CREATE_INFO
	createInfo.queueCreateInfoCount = u32(len(queueCreateInfos))
	createInfo.pQueueCreateInfos = raw_data(queueCreateInfos)
	createInfo.pEnabledFeatures = &features
	createInfo.enabledExtensionCount = u32(len(deviceExtensions))
	createInfo.ppEnabledExtensionNames = raw_data(deviceExtensions)

	if ENABLE_VALIDATION_LAYERS
	{
		createInfo.enabledLayerCount = u32(len(validationLayers))
		createInfo.ppEnabledLayerNames = raw_data(validationLayers)
	}
	else
	{
		createInfo.enabledLayerCount = 0
	}
	
	result := vk.CreateDevice(app.physicalDevice, &createInfo, nil, &app.device)
	if result != .SUCCESS
	{
		fmt.panicf("Failed to create logical device")
	}

	vk.GetDeviceQueue(app.device, indices.graphicsFamily.(u32), 0, &app.graphicsQueue)
	vk.GetDeviceQueue(app.device, indices.presentFamily.(u32), 0,  &app.presentQueue)
}

create_surface :: proc() 
{
	result := glfw.CreateWindowSurface(app.instance, app.window, nil, &app.surface)
	if result != .SUCCESS
	{
		fmt.panicf("Could not create window surface")
	}
}

cleanup_swapchain :: proc()
{
	for buffer in app.swapFramebuffers
	{
		vk.DestroyFramebuffer(app.device, buffer, nil)
	}
	
	for view in app.swapImageViews
	{
		vk.DestroyImageView(app.device, view, nil)
	}
	
	vk.DestroySwapchainKHR(app.device, app.swapchain, nil)
}

recreate_swapchain :: proc()
{
	// Pause the program while it is minimized
	for
	{
		if glfw.WindowShouldClose(app.window)
		{
			return
		}
		
		w, h := glfw.GetFramebufferSize(app.window)
		glfw.WaitEvents()
		if (w != 0 && h != 0) 
		{
			break
		}
	}

	vk.DeviceWaitIdle(app.device)
	cleanup_swapchain()
	
	create_swapchain()
	create_image_views()
	create_framebuffers()
}

create_swapchain :: proc()
{
	support := query_swapchain_support(app.physicalDevice)

	format := choose_swap_surface_format(&support.formats)
	mode   := choose_swap_present_mode(&support.presentModes)
	extent := choose_swap_extent(&support.capabilities)
	
	imageCount := support.capabilities.minImageCount + 1
	if support.capabilities.maxImageCount > 0 && imageCount > support.capabilities.maxImageCount
	{
		imageCount = support.capabilities.maxImageCount
	}

	createInfo: vk.SwapchainCreateInfoKHR
	createInfo.sType = .SWAPCHAIN_CREATE_INFO_KHR
	createInfo.surface = app.surface
	createInfo.minImageCount = imageCount
	createInfo.imageFormat = format.format
	createInfo.imageColorSpace = format.colorSpace
	createInfo.imageExtent = extent
	createInfo.imageArrayLayers = 1
	createInfo.imageUsage = {.COLOR_ATTACHMENT}

	indices := find_queue_families(app.physicalDevice)
	familyIndices := []u32 {indices.graphicsFamily.(u32), indices.presentFamily.(u32)}

	if indices.graphicsFamily != indices.presentFamily
	{
		createInfo.imageSharingMode = .CONCURRENT
		createInfo.queueFamilyIndexCount = 2
		createInfo.pQueueFamilyIndices = raw_data(familyIndices)
	}
	else
	{
		createInfo.imageSharingMode = .EXCLUSIVE
		createInfo.queueFamilyIndexCount = 0
		createInfo.pQueueFamilyIndices = nil
	}

	createInfo.preTransform = support.capabilities.currentTransform
	createInfo.compositeAlpha = {.OPAQUE}
	createInfo.presentMode = mode
	createInfo.clipped = true
	createInfo.oldSwapchain = NULL_HANDLE // FIXME maybe this is wrong hey

	result := vk.CreateSwapchainKHR(app.device, &createInfo, nil, &app.swapchain)
	if result != .SUCCESS
	{
		fmt.panicf("Failed to create swapchain")
	}

	vk.GetSwapchainImagesKHR(app.device, app.swapchain, &imageCount, nil)
	resize(&app.swapImages, imageCount)
	vk.GetSwapchainImagesKHR(app.device, app.swapchain, &imageCount, raw_data(app.swapImages))

	app.swapImageFormat = format.format
	app.swapExtent = extent
}

create_image_views :: proc()
{
	resize(&app.swapImageViews, len(app.swapImages))

	for i in 0..<len(app.swapImages)
	{
		app.swapImageViews[i] = create_image_view(app.swapImages[i], app.swapImageFormat, {.COLOR}, 1)
	}

}

read_file :: proc(name: string) -> []byte
{
	file, ok := os.read_entire_file_from_filename(name)
	if !ok do fmt.panicf("Could not read file called: %s", name)
	
	return file
}

create_render_pass :: proc()
{
	colorAttachment: vk.AttachmentDescription
	colorAttachment.format = app.swapImageFormat
	colorAttachment.samples = {._1}
	colorAttachment.loadOp = .CLEAR
	colorAttachment.storeOp = .STORE
	colorAttachment.stencilLoadOp = .DONT_CARE
	colorAttachment.stencilStoreOp = .DONT_CARE
	colorAttachment.initialLayout = .UNDEFINED
	colorAttachment.finalLayout = .PRESENT_SRC_KHR

	colorAttachmentRef: vk.AttachmentReference
	colorAttachmentRef.attachment = 0
	colorAttachmentRef.layout = .COLOR_ATTACHMENT_OPTIMAL

	depthAttachment: vk.AttachmentDescription
	depthAttachment.format = find_depth_format()
	depthAttachment.samples = {._1}
	depthAttachment.loadOp = .CLEAR
	depthAttachment.storeOp = .DONT_CARE
	depthAttachment.stencilLoadOp = .DONT_CARE
	depthAttachment.stencilStoreOp = .DONT_CARE
	depthAttachment.initialLayout = .UNDEFINED
	depthAttachment.finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL

	depthRef: vk.AttachmentReference
	depthRef.attachment = 1
	depthRef.layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL

	subpass: vk.SubpassDescription
	subpass.pipelineBindPoint = .GRAPHICS
	subpass.colorAttachmentCount = 1
	subpass.pColorAttachments = &colorAttachmentRef
	subpass.pDepthStencilAttachment = &depthRef
	
	dep: vk.SubpassDependency
	dep.srcSubpass = vk.SUBPASS_EXTERNAL
	dep.dstSubpass = 0
	dep.srcStageMask = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS}
	dep.srcAccessMask = nil 
	dep.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS}
	dep.dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE}

	attachments := []vk.AttachmentDescription {colorAttachment, depthAttachment}
	
	renderPassInfo: vk.RenderPassCreateInfo
	renderPassInfo.sType = .RENDER_PASS_CREATE_INFO
	renderPassInfo.attachmentCount = u32(len(attachments))
	renderPassInfo.pAttachments = raw_data(attachments)
	renderPassInfo.subpassCount = 1
	renderPassInfo.pSubpasses = &subpass
	renderPassInfo.dependencyCount = 1
	renderPassInfo.pDependencies = &dep

	if vk.CreateRenderPass(app.device, &renderPassInfo, nil, &app.renderPass) != .SUCCESS
	{
		fmt.panicf("Failed to create render pass")
	}
}

create_descriptor_set_layout :: proc()
{
	vertexBinding: vk.DescriptorSetLayoutBinding
	vertexBinding.binding = 0
	vertexBinding.descriptorCount = 1
	vertexBinding.descriptorType = .UNIFORM_BUFFER
	vertexBinding.stageFlags = {.VERTEX}
	
	samplerBinding: vk.DescriptorSetLayoutBinding
	samplerBinding.binding = 1
	samplerBinding.descriptorCount = 1
	samplerBinding.descriptorType = .COMBINED_IMAGE_SAMPLER
	samplerBinding.stageFlags = {.FRAGMENT}

	bindings := []vk.DescriptorSetLayoutBinding {vertexBinding, samplerBinding}
	layoutInfo: vk.DescriptorSetLayoutCreateInfo
	layoutInfo.sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO
	layoutInfo.bindingCount = u32(len(bindings))
	layoutInfo.pBindings = raw_data(bindings)

	result := vk.CreateDescriptorSetLayout(app.device, &layoutInfo, nil, &app.descriptorSetLayout) 
	if result != .SUCCESS
	{
		fmt.panicf("Failed to create descriptor set layout %v", result)
	}
}

create_graphics_pipeline :: proc()
{
	vertCode := read_file("res/shaders/vert.spv")
	fragCode := read_file("res/shaders/frag.spv")

	vertModule := create_shader_module(vertCode)
	fragModule := create_shader_module(fragCode)

	vertInfo: vk.PipelineShaderStageCreateInfo
	vertInfo.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
	vertInfo.stage = {.VERTEX}
	vertInfo.module = vertModule
	vertInfo.pName = "main"

	fragInfo: vk.PipelineShaderStageCreateInfo
	fragInfo.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
	fragInfo.stage = {.FRAGMENT}
	fragInfo.module = fragModule
	fragInfo.pName = "main"

	shaderStages := []vk.PipelineShaderStageCreateInfo {vertInfo, fragInfo}
	
	bindingDesc := get_binding_description()
	attributeDesc := get_attribute_description()
	
	vertInputInfo: vk.PipelineVertexInputStateCreateInfo
	vertInputInfo.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
	vertInputInfo.vertexBindingDescriptionCount = 1
	vertInputInfo.vertexAttributeDescriptionCount = u32(len(attributeDesc))
	vertInputInfo.pVertexBindingDescriptions = &bindingDesc
	vertInputInfo.pVertexAttributeDescriptions = raw_data(attributeDesc)

	inputAssembly: vk.PipelineInputAssemblyStateCreateInfo
	inputAssembly.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
	inputAssembly.topology = .TRIANGLE_LIST

	viewport: vk.Viewport
	viewport.width = f32(app.swapExtent.width)
	viewport.height = f32(app.swapExtent.height)
	viewport.minDepth = 0
	viewport.maxDepth = 1

	scissor: vk.Rect2D
	scissor.extent = app.swapExtent

	rasterizer: vk.PipelineRasterizationStateCreateInfo
	rasterizer.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO
	rasterizer.depthClampEnable = false
	rasterizer.rasterizerDiscardEnable = false
	rasterizer.polygonMode = .FILL
	rasterizer.lineWidth = 1
	rasterizer.cullMode = {}
	rasterizer.frontFace = .CLOCKWISE
	rasterizer.depthBiasEnable = false

	multisamp: vk.PipelineMultisampleStateCreateInfo
	multisamp.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
	multisamp.sampleShadingEnable = false
	multisamp.rasterizationSamples = {._1}
	multisamp.minSampleShading = 1
	multisamp.pSampleMask = nil
	multisamp.alphaToCoverageEnable = false
	multisamp.alphaToOneEnable = false

	colorBlendAttachment: vk.PipelineColorBlendAttachmentState
	colorBlendAttachment.blendEnable = false
	colorBlendAttachment.colorWriteMask = {.R, .G, .B, .A}

	colorBlendInfo: vk.PipelineColorBlendStateCreateInfo
	colorBlendInfo.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
	colorBlendInfo.logicOpEnable = false
	colorBlendInfo.logicOp = .COPY
	colorBlendInfo.attachmentCount = 1
	colorBlendInfo.pAttachments = &colorBlendAttachment

	depthStencil: vk.PipelineDepthStencilStateCreateInfo
	depthStencil.sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
	depthStencil.depthTestEnable = true
	depthStencil.depthWriteEnable = true
	depthStencil.depthCompareOp = .LESS
	depthStencil.depthBoundsTestEnable = false
	depthStencil.stencilTestEnable = false

	pipeLayoutInfo: vk.PipelineLayoutCreateInfo
	pipeLayoutInfo.sType = .PIPELINE_LAYOUT_CREATE_INFO
	pipeLayoutInfo.setLayoutCount = 1
	pipeLayoutInfo.pSetLayouts = &app.descriptorSetLayout
	if vk.CreatePipelineLayout(app.device, &pipeLayoutInfo, nil, &app.pipelineLayout) != .SUCCESS
	{
		fmt.panicf("Could not create pipeline layout")
	}
	
	dynamicStates := []vk.DynamicState {.VIEWPORT, .SCISSOR}
	
	dynInfo: vk.PipelineDynamicStateCreateInfo  
	dynInfo.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
	dynInfo.dynamicStateCount = u32(len(dynamicStates))
	dynInfo.pDynamicStates = raw_data(dynamicStates)

	viewportState: vk.PipelineViewportStateCreateInfo
	viewportState.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
	viewportState.viewportCount = 1
	viewportState.scissorCount = 1

	pipelineInfo: vk.GraphicsPipelineCreateInfo
	pipelineInfo.sType = .GRAPHICS_PIPELINE_CREATE_INFO
	pipelineInfo.stageCount = 2
	pipelineInfo.pStages = raw_data(shaderStages)
	pipelineInfo.pVertexInputState = &vertInputInfo
	pipelineInfo.pInputAssemblyState = &inputAssembly
	pipelineInfo.pViewportState = &viewportState
	pipelineInfo.pRasterizationState = &rasterizer
	pipelineInfo.pMultisampleState = &multisamp
	pipelineInfo.pDepthStencilState = nil
	pipelineInfo.pColorBlendState = &colorBlendInfo
	pipelineInfo.pDynamicState = &dynInfo
	pipelineInfo.layout = app.pipelineLayout
	pipelineInfo.renderPass = app.renderPass
	pipelineInfo.subpass = 0
	pipelineInfo.basePipelineHandle = NULL_HANDLE
	pipelineInfo.basePipelineIndex = -1
	pipelineInfo.pDepthStencilState = &depthStencil

	if vk.CreateGraphicsPipelines(app.device, NULL_HANDLE, 1, &pipelineInfo, nil, &app.graphicsPipeline) != .SUCCESS
	{
		fmt.panicf("Failed to create graphics pipeline")
	}
	
	vk.DestroyShaderModule(app.device, vertModule, nil)
	vk.DestroyShaderModule(app.device, fragModule, nil)
}

create_framebuffers :: proc()
{
	resize(&app.swapFramebuffers, len(app.swapImageViews))
	
	for view, i in app.swapImageViews
	{
		attachments: []vk.ImageView = {view, app.depthImageView}

		framebufferInfo: vk.FramebufferCreateInfo
		framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
		framebufferInfo.renderPass = app.renderPass
		framebufferInfo.attachmentCount = u32(len(attachments))
		framebufferInfo.pAttachments = raw_data(attachments)
		framebufferInfo.width = app.swapExtent.width
		framebufferInfo.height = app.swapExtent.height
		framebufferInfo.layers = 1

		if vk.CreateFramebuffer(app.device, &framebufferInfo, nil, &app.swapFramebuffers[i]) != .SUCCESS
		{
			fmt.panicf("Failed to create framebuffer")
		}
	}
	
}

create_command_pool :: proc()
{
	indices := find_queue_families(app.physicalDevice)
	poolInfo: vk.CommandPoolCreateInfo
	poolInfo.sType = .COMMAND_POOL_CREATE_INFO
	poolInfo.flags = {.RESET_COMMAND_BUFFER}
	poolInfo.queueFamilyIndex = indices.graphicsFamily.(u32)

	if vk.CreateCommandPool(app.device, &poolInfo, nil, &app.commandPool) != .SUCCESS
	{
		fmt.panicf("Failed to create commandpool")
	}
}

find_supported_format :: proc(candidates: []vk.Format, tiling : vk.ImageTiling, features: vk.FormatFeatureFlags) -> vk.Format
{
	props: vk.FormatProperties
	for format in candidates
	{
		vk.GetPhysicalDeviceFormatProperties(app.physicalDevice, format, &props)
		if tiling == .LINEAR && (props.linearTilingFeatures & features) == features
		{
			return format
		}
		else if tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features
		{
			return format
		}
	}

	fmt.panicf("Failed to find supported format")
}

has_stencil_component :: proc(format: vk.Format) -> bool
{
	return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT
}

find_depth_format :: proc() -> vk.Format
{
	return find_supported_format(
		{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT}
	)
}

create_depth_resources :: proc()
{
	depthFormat := find_depth_format()
	
	create_image(app.swapExtent.width, app.swapExtent.height, 1, depthFormat, .OPTIMAL, 
		{.DEPTH_STENCIL_ATTACHMENT}, {.DEVICE_LOCAL}, &app.depthImage, &app.depthImageMemory) 
	app.depthImageView = create_image_view(app.depthImage, depthFormat, {.DEPTH}, 1)
	
	transition_image_layout(app.depthImage, depthFormat, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL, 1)
}

create_image :: proc(width, height: u32, mipLevels: u32, format: vk.Format, tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags, props: vk.MemoryPropertyFlags, image:  ^vk.Image, imageMem: ^vk.DeviceMemory)
{
	
	imageInfo: vk.ImageCreateInfo
	imageInfo.sType = .IMAGE_CREATE_INFO
	imageInfo.imageType = .D2
	imageInfo.extent.width =  width
	imageInfo.extent.height = height
	imageInfo.extent.depth = 1
	imageInfo.mipLevels = mipLevels
	imageInfo.arrayLayers = 1
	imageInfo.format = format
	imageInfo.tiling = tiling
	imageInfo.initialLayout = .UNDEFINED
	imageInfo.usage = usage
	imageInfo.sharingMode = .EXCLUSIVE
	imageInfo.samples = {._1}

	if vk.CreateImage(app.device, &imageInfo, nil, image) != .SUCCESS
	{
		fmt.panicf("Failed to create image")
	}

	memReqs: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(app.device, image^, &memReqs)
	allocInfo: vk.MemoryAllocateInfo
	allocInfo.sType = .MEMORY_ALLOCATE_INFO
	allocInfo.allocationSize = memReqs.size
	allocInfo.memoryTypeIndex = find_memory_type(memReqs.memoryTypeBits, props)

	if vk.AllocateMemory(app.device, &allocInfo, nil, imageMem) != .SUCCESS
	{
		fmt.panicf("Failed to allocate image memory")
	}
		
	vk.BindImageMemory(app.device, image^, imageMem^, 0)
}

create_texture_image :: proc()
{
	// Load image from disk
	width, height, channels: c.int
	image := stbi.load("res/tex/spitter_col.png", &width, &height, &channels, 4)
	app.mipLevels = u32(math.floor_f32(math.log2_f32(max(f32(width), f32(height)))) + 1)
	if image == nil
	{
		fmt.panicf("Failed to load texture image")
	}
	defer stbi.image_free(image)
	
	imgSize := vk.DeviceSize(width * height * 4)
	stagingBuf: vk.Buffer
	stagingMem: vk.DeviceMemory
	create_buffer(imgSize, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &stagingBuf, &stagingMem)

	data: rawptr
	vk.MapMemory(app.device, stagingMem, 0, imgSize, nil, &data)
	mem.copy(data, image, int(imgSize))
	vk.UnmapMemory(app.device, stagingMem)

	create_image(u32(width), u32(height), app.mipLevels, vk.Format.R8G8B8A8_SRGB, vk.ImageTiling.OPTIMAL, 
		{.TRANSFER_DST, .TRANSFER_SRC, .SAMPLED}, {.DEVICE_LOCAL}, &app.textureImage, &app.textureMemory)
	
	transition_image_layout(app.textureImage, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL, app.mipLevels)
		copy_buffer_to_image(stagingBuf, app.textureImage, u32(width), u32(height))
	// transition_image_layout(app.textureImage, .R8G8B8A8_SRGB, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, app.mipLevels)
	generate_mipmaps(app.textureImage, .R8G8B8A8_SRGB, u32(width), u32(height), app.mipLevels)

	vk.DestroyBuffer(app.device, stagingBuf, nil)
	vk.FreeMemory(app.device, stagingMem, nil)
}

generate_mipmaps :: proc(image: vk.Image, format: vk.Format, width, height: u32, mipLevels: u32)
{
	// LInear blit support check
	props: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(app.physicalDevice, format, &props)
	if .SAMPLED_IMAGE_FILTER_LINEAR in props.optimalTilingFeatures == false
	{
		fmt.panicf("Texture image does not support linear blitting")
	}
	mipWidth := i32(width)
	mipHeight := i32(height)
	
	cmdBuf := begin_single_time_commands()
	barrier: vk.ImageMemoryBarrier
	barrier.sType = .IMAGE_MEMORY_BARRIER
	barrier.image = image
	barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
	barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
	barrier.subresourceRange.aspectMask = {.COLOR}
	barrier.subresourceRange.levelCount = 1
	barrier.subresourceRange.layerCount = 1

	for i in 1..<mipLevels
	{
		barrier.subresourceRange.baseMipLevel = i - 1
		barrier.oldLayout = .TRANSFER_DST_OPTIMAL
		barrier.newLayout = .TRANSFER_SRC_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.TRANSFER_READ}

		vk.CmdPipelineBarrier(
			cmdBuf, {.TRANSFER}, {.TRANSFER}, nil,
			0, nil,
			0, nil,
			1, &barrier
		)

		blit: vk.ImageBlit
		blit.srcOffsets[0] = {0, 0, 0}
		blit.srcOffsets[1] = {mipWidth, mipHeight, 1}
		blit.srcSubresource.aspectMask = {.COLOR}
		blit.srcSubresource.mipLevel = i - 1
		blit.srcSubresource.layerCount = 1

		blit.dstOffsets[0] = {0, 0, 0}
		blit.dstOffsets[1] = {mipWidth / 2 if mipWidth > 1 else 1, mipHeight / 2 if mipHeight > 1 else 1, 1}
		blit.dstSubresource.aspectMask = {.COLOR}
		blit.dstSubresource.mipLevel = i
		blit.dstSubresource.layerCount = 1

		vk.CmdBlitImage(
			cmdBuf, 
			image, .TRANSFER_SRC_OPTIMAL,
			image, .TRANSFER_DST_OPTIMAL, 
			1, &blit,
			.NEAREST
		)

		barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
		barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
		barrier.dstAccessMask = {.TRANSFER_READ}
		barrier.dstAccessMask = {.SHADER_READ}
		
		vk.CmdPipelineBarrier(
			cmdBuf,
			{.TRANSFER}, {.FRAGMENT_SHADER}, nil,
			0, nil,
			0, nil,
			1, &barrier
		)

		if mipWidth  > 1 do mipWidth  /= 2
		if mipHeight > 1 do mipHeight /= 2
	}

	barrier.subresourceRange.baseMipLevel = mipLevels - 1
	barrier.oldLayout = .TRANSFER_DST_OPTIMAL
	barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
	barrier.srcAccessMask = {.TRANSFER_WRITE}
	barrier.dstAccessMask = {.SHADER_READ}

	vk.CmdPipelineBarrier(
		cmdBuf, 
		{.TRANSFER}, {.FRAGMENT_SHADER}, nil,
		0, nil,
		0, nil,
		1, &barrier
	)
	
	end_single_time_commands(cmdBuf)
	
}

create_image_view :: proc(image: vk.Image, format: vk.Format, aspectFlags: vk.ImageAspectFlags, mipLevels: u32) -> vk.ImageView
{
	viewInfo: vk.ImageViewCreateInfo
	viewInfo.sType = .IMAGE_VIEW_CREATE_INFO
	viewInfo.image = image
	viewInfo.viewType = .D2
	viewInfo.format = format
	viewInfo.subresourceRange.aspectMask = aspectFlags
	viewInfo.subresourceRange.levelCount = mipLevels
	viewInfo.subresourceRange.layerCount = 1
	
	view: vk.ImageView
	if vk.CreateImageView(app.device, &viewInfo, nil, &view) != .SUCCESS
	{
		fmt.panicf("Failed to create texture image view")
	}

	return view
}

create_texture_image_view :: proc()
{
	app.textureImageView = create_image_view(app.textureImage, .R8G8B8A8_SRGB, {.COLOR}, app.mipLevels)
}

create_texture_sampler :: proc()
{
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(app.physicalDevice, &props)
	
	samplerInfo: vk.SamplerCreateInfo
	samplerInfo.sType = .SAMPLER_CREATE_INFO
	samplerInfo.minFilter = .NEAREST
	samplerInfo.magFilter = .NEAREST
	samplerInfo.addressModeU = .REPEAT
	samplerInfo.addressModeV = .REPEAT
	samplerInfo.addressModeW = .REPEAT
	samplerInfo.anisotropyEnable = true
	samplerInfo.maxAnisotropy = props.limits.maxSamplerAnisotropy
	samplerInfo.borderColor = .INT_OPAQUE_BLACK
	samplerInfo.unnormalizedCoordinates = false
	samplerInfo.compareEnable = false
	samplerInfo.compareOp = .ALWAYS
	samplerInfo.mipmapMode = .NEAREST
	samplerInfo.minLod = 0
	samplerInfo.maxLod = f32(app.mipLevels)

	if vk.CreateSampler(app.device, &samplerInfo, nil, &app.textureSampler) != .SUCCESS
	{
		fmt.panicf("Failed to create texture sampler")
	}
}

transition_image_layout :: proc(image: vk.Image, format: vk.Format, 
oldLayout: vk.ImageLayout, newLayout: vk.ImageLayout, mipLevels: u32)
{
	cmdBuf := begin_single_time_commands()
	
	barrier : vk.ImageMemoryBarrier
	barrier.sType = .IMAGE_MEMORY_BARRIER
	barrier.oldLayout = oldLayout
	barrier.newLayout = newLayout
	barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
	barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
	barrier.image = image
	barrier.subresourceRange.aspectMask = {.COLOR}
	barrier.subresourceRange.baseMipLevel = 0
	barrier.subresourceRange.levelCount = mipLevels
	barrier.subresourceRange.baseArrayLayer = 0
	barrier.subresourceRange.layerCount = 1
	barrier.srcAccessMask = nil // TODO
	barrier.dstAccessMask = nil // TODO

	srcStage: vk.PipelineStageFlags
	dstStage: vk.PipelineStageFlags
	
	if oldLayout == .UNDEFINED && newLayout == .TRANSFER_DST_OPTIMAL
	{
		barrier.srcAccessMask = nil
		barrier.dstAccessMask = {.TRANSFER_WRITE}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.TRANSFER}
	}
	else if oldLayout == .TRANSFER_DST_OPTIMAL && newLayout == .SHADER_READ_ONLY_OPTIMAL
	{
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}

		srcStage = {.TRANSFER}
		dstStage = {.FRAGMENT_SHADER}
	}
	else if oldLayout == .UNDEFINED && newLayout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
	{
		barrier.srcAccessMask = nil
		barrier.dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.EARLY_FRAGMENT_TESTS}
	}
	else
	{
		fmt.panicf("Unsupported layout transition")
	}

	if newLayout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
	{
		barrier.subresourceRange.aspectMask = {.DEPTH}

		if has_stencil_component(format)
		{
			barrier.subresourceRange.aspectMask += {.STENCIL}
		}
	}
	else
	{
		barrier.subresourceRange.aspectMask = {.COLOR}
	}

	vk.CmdPipelineBarrier(
		cmdBuf,
		srcStage, dstStage,
		nil,
		0, nil,
		0, nil,
		1, &barrier
	) 
	
	end_single_time_commands(cmdBuf)
}

create_buffer :: proc(size: vk.DeviceSize, usage: vk.BufferUsageFlags, props: vk.MemoryPropertyFlags,
buf: ^vk.Buffer, bufMem: ^vk.DeviceMemory)
{
	
	bufferInfo: vk.BufferCreateInfo
	bufferInfo.sType = .BUFFER_CREATE_INFO
	bufferInfo.size = size
	bufferInfo.usage = usage
	bufferInfo.sharingMode = .EXCLUSIVE

	if vk.CreateBuffer(app.device, &bufferInfo, nil, buf) != .SUCCESS
	{
		fmt.panicf("Failed to create buffer")
	}

	memReqs: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(app.device, buf^, &memReqs)

	allocInfo: vk.MemoryAllocateInfo
	allocInfo.sType = .MEMORY_ALLOCATE_INFO
	allocInfo.allocationSize = memReqs.size
	allocInfo.memoryTypeIndex = find_memory_type(memReqs.memoryTypeBits, props)

	if vk.AllocateMemory(app.device, &allocInfo, nil, bufMem) != .SUCCESS
	{
		fmt.panicf("Failed to allocate memory for vertex buffer")
	}

	vk.BindBufferMemory(app.device, buf^, bufMem^, 0)
}

create_vertex_buffer :: proc()
{
	bufSize := vk.DeviceSize(size_of(app.vertices[0]) * len(app.vertices))
	stagingBuf: vk.Buffer
	stagingMem: vk.DeviceMemory
	create_buffer(bufSize, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &stagingBuf, &stagingMem)

	data: rawptr
	vk.MapMemory(app.device, stagingMem, 0, bufSize, nil, &data)
	mem.copy(data, &app.vertices[0], int(bufSize))
	vk.UnmapMemory(app.device, stagingMem)

	create_buffer(bufSize, {.TRANSFER_DST, .VERTEX_BUFFER}, {.DEVICE_LOCAL}, &app.vertexBuffer, &app.vertexBufferMemory)
	copy_buffer(stagingBuf, app.vertexBuffer, bufSize)

	vk.DestroyBuffer(app.device, stagingBuf, nil)
	vk.FreeMemory(app.device, stagingMem, nil)
}

create_index_buffer :: proc()
{
	bufSize := vk.DeviceSize(size_of(app.indices[0]) * u16(len(app.indices)))
	
	stagingBuf: vk.Buffer
	stagingMem: vk.DeviceMemory
	create_buffer(bufSize, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &stagingBuf, &stagingMem)

	data: rawptr
	vk.MapMemory(app.device, stagingMem, 0, bufSize, nil, &data)
	mem.copy(data, &app.indices[0], int(bufSize))
	vk.UnmapMemory(app.device, stagingMem)

	create_buffer(bufSize, {.TRANSFER_DST, .INDEX_BUFFER}, {.DEVICE_LOCAL}, &app.indexBuffer, &app.indexBufferMemory)
	copy_buffer(stagingBuf, app.indexBuffer, bufSize)
	
	vk.DestroyBuffer(app.device, stagingBuf, nil)
	vk.FreeMemory(app.device, stagingMem, nil)
}

create_uniform_buffers :: proc()
{
	bufSize := vk.DeviceSize(size_of(UniformBufferObject))

	resize(&app.uniformBuffers,       MAX_FRAMES_IN_FLIGHT)
	resize(&app.uniformBuffersMemory, MAX_FRAMES_IN_FLIGHT)
	resize(&app.uniformBuffersMapped, MAX_FRAMES_IN_FLIGHT)

	for i in 0..<MAX_FRAMES_IN_FLIGHT
	{
		create_buffer(bufSize, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, &app.uniformBuffers[i], &app.uniformBuffersMemory[i])
		vk.MapMemory(app.device, app.uniformBuffersMemory[i], 0, bufSize, nil, &app.uniformBuffersMapped[i])
	}
}

create_descriptor_pool :: proc()
{
	poolSizes := make([]vk.DescriptorPoolSize, 2)
	defer delete(poolSizes)
	
	poolSizes[0].type = .UNIFORM_BUFFER
	poolSizes[0].descriptorCount = u32(MAX_FRAMES_IN_FLIGHT)
	poolSizes[1].type = .COMBINED_IMAGE_SAMPLER
	poolSizes[1].descriptorCount = u32(MAX_FRAMES_IN_FLIGHT)

	poolInfo: vk.DescriptorPoolCreateInfo
	poolInfo.sType = .DESCRIPTOR_POOL_CREATE_INFO
	poolInfo.poolSizeCount = u32(len(poolSizes))
	poolInfo.pPoolSizes = raw_data(poolSizes)
	poolInfo.maxSets = u32(MAX_FRAMES_IN_FLIGHT)

	if vk.CreateDescriptorPool(app.device, &poolInfo, nil, &app.descriptorPool) != .SUCCESS
	{
		fmt.panicf("Failed to create descriptor pool")
	}
}

create_descriptor_sets :: proc()
{	
	layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
	for i in 0..<MAX_FRAMES_IN_FLIGHT
	{
		layouts[i] = app.descriptorSetLayout
	}
	
	allocInfo: vk.DescriptorSetAllocateInfo
	allocInfo.sType = .DESCRIPTOR_SET_ALLOCATE_INFO
	allocInfo.descriptorPool = app.descriptorPool
	allocInfo.descriptorSetCount = u32(MAX_FRAMES_IN_FLIGHT)
	allocInfo.pSetLayouts = raw_data(layouts)

	resize(&app.descriptorSets, MAX_FRAMES_IN_FLIGHT)
	if vk.AllocateDescriptorSets(app.device, &allocInfo, raw_data(app.descriptorSets)) != .SUCCESS
	{
		fmt.panicf("Failed to allocate descriptor sets")
	}

	for i in 0..<MAX_FRAMES_IN_FLIGHT
	{
		descWrites := make([]vk.WriteDescriptorSet, 2)
		
		bufferInfo: vk.DescriptorBufferInfo
		bufferInfo.buffer = app.uniformBuffers[i]
		bufferInfo.offset = 0
		bufferInfo.range = size_of(UniformBufferObject)

		descWrites[0].sType = .WRITE_DESCRIPTOR_SET
		descWrites[0].dstSet = app.descriptorSets[i]
		descWrites[0].dstBinding = 0
		descWrites[0].dstArrayElement = 0
		descWrites[0].descriptorType = .UNIFORM_BUFFER
		descWrites[0].descriptorCount = 1
		descWrites[0].pBufferInfo = &bufferInfo

		imageInfo: vk.DescriptorImageInfo
		imageInfo.imageLayout = .SHADER_READ_ONLY_OPTIMAL
		imageInfo.imageView = app.textureImageView
		imageInfo.sampler = app.textureSampler

		descWrites[1].sType = .WRITE_DESCRIPTOR_SET
		descWrites[1].dstSet = app.descriptorSets[i]
		descWrites[1].dstBinding = 1
		descWrites[1].dstArrayElement = 0
		descWrites[1].descriptorType = .COMBINED_IMAGE_SAMPLER
		descWrites[1].descriptorCount = 1
		descWrites[1].pImageInfo = &imageInfo
		
		vk.UpdateDescriptorSets(app.device, u32(len(descWrites)), raw_data(descWrites), 0, nil)
	}
}

update_uniform_buffer :: proc(img: u32)
{
	sin := f32(math.sin(glfw.GetTime()))
	ubo: UniformBufferObject
	ubo.model = translate_mat({0, 0, 0})
	ubo.model *= rotate_mat(f32(glfw.GetTime()), {0, 1, 0})
	ubo.model *= scale_mat(0.5)
	
	camPos := camera.position
	
	ubo.view  = linalg.matrix4_look_at_f32(camPos, camPos + {0, 0, 1}, {0, -1, 0}, true)
	// ubo.view *= translate_mat({0, 0, -3})
	// ubo.view  = linalg.matrix4_look_at_f32(camPos, 0, {0, -1, 0}, false)
	ubo.proj  = linalg.matrix4_perspective_f32(math.PI / 2, f32(app.swapExtent.width) / f32(app.swapExtent.height), 0.1, 100, true)
	mem.copy(app.uniformBuffersMapped[img], &ubo, size_of(UniformBufferObject))
}

begin_single_time_commands :: proc() -> vk.CommandBuffer
{
	
	allocInfo: vk.CommandBufferAllocateInfo
	allocInfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
	allocInfo.level = .PRIMARY
	allocInfo.commandPool = app.commandPool
	allocInfo.commandBufferCount = 1

	cmdBuf: vk.CommandBuffer
	vk.AllocateCommandBuffers(app.device, &allocInfo, &cmdBuf)

	beginInfo: vk.CommandBufferBeginInfo
	beginInfo.sType = .COMMAND_BUFFER_BEGIN_INFO
	beginInfo.flags = {.ONE_TIME_SUBMIT}
	
	vk.BeginCommandBuffer(cmdBuf, &beginInfo)

	return cmdBuf
}

end_single_time_commands :: proc(cmdBuf: vk.CommandBuffer)
{
	cmdBuf := cmdBuf
	vk.EndCommandBuffer(cmdBuf)

	submitInfo: vk.SubmitInfo
	submitInfo.sType = .SUBMIT_INFO
	submitInfo.commandBufferCount = 1
	submitInfo.pCommandBuffers = &cmdBuf
	
	vk.QueueSubmit(app.graphicsQueue, 1, &submitInfo, NULL_HANDLE)
	vk.QueueWaitIdle(app.graphicsQueue)

	vk.FreeCommandBuffers(app.device, app.commandPool, 1, &cmdBuf)
}

copy_buffer :: proc(src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize)
{
	cmdBuf := begin_single_time_commands()
	
	region: vk.BufferCopy
	region.size = size
	vk.CmdCopyBuffer(cmdBuf, src, dst, 1, &region)
	
	end_single_time_commands(cmdBuf)
}

copy_buffer_to_image :: proc(buffer: vk.Buffer, image: vk.Image, width, height: u32)
{
	cmdBuf := begin_single_time_commands()

	region: vk.BufferImageCopy
	region.imageSubresource.aspectMask = {.COLOR}
	region.imageSubresource.layerCount = 1
	region.imageExtent = {
		width = width,
		height = height,
		depth = 1
	}

	vk.CmdCopyBufferToImage(
		cmdBuf,
		buffer,
		image,
		.TRANSFER_DST_OPTIMAL,
		1,
		&region
	)
	
	end_single_time_commands(cmdBuf)
}

find_memory_type :: proc(filter: u32, flags: vk.MemoryPropertyFlags) -> u32
{
	memProps: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(app.physicalDevice, &memProps)

	for i in 0..<memProps.memoryTypeCount
	{
		if filter & (1 << i) != 0 && memProps.memoryTypes[i].propertyFlags & flags == flags // Maybe fucked
		{
			return u32(i)
		}
	}

	fmt.panicf("Failed to find suitable memory type")
}

create_command_buffers :: proc()
{
	resize(&app.commandBuffers, MAX_FRAMES_IN_FLIGHT)
	allocInfo: vk.CommandBufferAllocateInfo
	allocInfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
	allocInfo.commandPool = app.commandPool
	allocInfo.level = .PRIMARY
	allocInfo.commandBufferCount = u32(len(app.commandBuffers))

	if vk.AllocateCommandBuffers(app.device, &allocInfo, raw_data(app.commandBuffers)) != .SUCCESS
	{
		fmt.panicf("Failed to allocate command buffer")
	}
}

create_sync_objects :: proc()
{
	resize(&app.imgAvailableSemaphores,   MAX_FRAMES_IN_FLIGHT)
	resize(&app.renderFinishedSemaphores, MAX_FRAMES_IN_FLIGHT)
	resize(&app.inFlightFences,           MAX_FRAMES_IN_FLIGHT)
	
	semaInfo: vk.SemaphoreCreateInfo
	semaInfo.sType = .SEMAPHORE_CREATE_INFO
	
	fenceInfo: vk.FenceCreateInfo
	fenceInfo.sType = .FENCE_CREATE_INFO
	fenceInfo.flags = {.SIGNALED}

	for i in 0..<MAX_FRAMES_IN_FLIGHT
	{
		if  vk.CreateSemaphore(app.device, &semaInfo, nil, &app.imgAvailableSemaphores[i])   != .SUCCESS ||
		    vk.CreateSemaphore(app.device, &semaInfo, nil, &app.renderFinishedSemaphores[i]) != .SUCCESS ||
		    vk.CreateFence(app.device, &fenceInfo, nil, &app.inFlightFences[i])              != .SUCCESS
		{
			fmt.panicf("Failed to create synchronization objects for a frame")
		}
	}
}

record_command_buffer :: proc(cmdBuf: vk.CommandBuffer, index: u32)
{
	beginInfo: vk.CommandBufferBeginInfo
	beginInfo.sType = .COMMAND_BUFFER_BEGIN_INFO

	if vk.BeginCommandBuffer(cmdBuf, &beginInfo) != .SUCCESS
	{
		fmt.panicf("Failed to begin recording command buffer")
	}

	renderInfo: vk.RenderPassBeginInfo
	renderInfo.sType = .RENDER_PASS_BEGIN_INFO
	renderInfo.renderPass = app.renderPass
	renderInfo.framebuffer = app.swapFramebuffers[index]
	renderInfo.renderArea.offset = {0, 0}
	renderInfo.renderArea.extent = app.swapExtent

	col: vk.ClearColorValue = {float32 = [4]f32{0, 0, 0, 1}}
	depthValue: vk.ClearDepthStencilValue = {depth = 1, stencil = 0}
	clearValues: []vk.ClearValue = {
		{color = col},
		{depthStencil = depthValue}
	}
	renderInfo.clearValueCount = u32(len(clearValues))
	renderInfo.pClearValues = raw_data(clearValues)

	vk.CmdBeginRenderPass(cmdBuf, &renderInfo, .INLINE)
	vk.CmdBindPipeline(cmdBuf, .GRAPHICS, app.graphicsPipeline)

	vertexBuffers: []vk.Buffer = {app.vertexBuffer}
	deviceOffsets: []vk.DeviceSize = {0}
	vk.CmdBindVertexBuffers(cmdBuf, 0, 1, raw_data(vertexBuffers), raw_data(deviceOffsets))

	vk.CmdBindIndexBuffer(cmdBuf, app.indexBuffer, 0, .UINT16)

	vk.CmdBindDescriptorSets(cmdBuf, .GRAPHICS, app.pipelineLayout, 0, 1, &app.descriptorSets[app.currentFrame], 0, nil)

	viewport: vk.Viewport
	viewport.width = f32(app.swapExtent.width)
	viewport.height = f32(app.swapExtent.height)
	viewport.minDepth = 0
	viewport.maxDepth = 1
	vk.CmdSetViewport(cmdBuf, 0, 1, &viewport)

	scissor: vk.Rect2D
	scissor.offset = {0, 0}
	scissor.extent = app.swapExtent
	vk.CmdSetScissor(cmdBuf, 0, 1, &scissor)

	// vk.CmdDraw(buffer, u32(len(vertices)), 1, 0, 0)
	vk.CmdDrawIndexed(cmdBuf, u32(len(app.indices)), 1, 0, 0, 0)
	vk.CmdEndRenderPass(cmdBuf)

	if vk.EndCommandBuffer(cmdBuf) != .SUCCESS
	{
		fmt.panicf("Failed to record command buffer")
	}
}

create_shader_module :: proc(code: []byte) -> vk.ShaderModule
{
	code := code
	createInfo: vk.ShaderModuleCreateInfo
	createInfo.sType = .SHADER_MODULE_CREATE_INFO
	createInfo.codeSize = len(code)
	
	// FIX Aligment maybe fucked
	createInfo.pCode = cast(^u32)raw_data(code)

	shaderModule: vk.ShaderModule
	if vk.CreateShaderModule(app.device, &createInfo, nil, &shaderModule) != .SUCCESS
	{
		fmt.panicf("Failed to create shader module")
	}

	return shaderModule
}

is_device_suitable :: proc(device: vk.PhysicalDevice) -> bool
{
	features: vk.PhysicalDeviceFeatures
	props:    vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceFeatures(device, &features)
	vk.GetPhysicalDeviceProperties(device, &props)

	indices := find_queue_families(device)
	extSupported := check_device_extension_support(device)

	isSwapchainAdequate := false
	if extSupported
	{
		details := query_swapchain_support(device)
		if len(details.formats) > 0 && len(details.presentModes) > 0
		{
			isSwapchainAdequate = true
		}
	}
	
	return is_family_indices_complete(&indices) && extSupported && isSwapchainAdequate && features.samplerAnisotropy
}

check_device_extension_support :: proc(device: vk.PhysicalDevice) -> bool
{
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil)
	
	availableExts := make([]vk.ExtensionProperties, count)
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(availableExts))

	builder: strings.Builder
	for required in deviceExtensions
	{
		found := false
		for &available in availableExts
		{
			strings.builder_reset(&builder)
			strings.write_bytes(&builder, available.extensionName[0:len(required)])
			str := strings.to_string(builder)
			if strings.compare(string(required), str) == 0
			{
				found = true
				break
			}
		}

		if !found
		{
			fmt.panicf("Could not find device extension properties")
		}
	}
	
	return true
}

query_swapchain_support :: proc(device: vk.PhysicalDevice) -> SwapchainSupportDetails
{
	details: SwapchainSupportDetails
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, app.surface, &details.capabilities)

	formatCount: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(device, app.surface, &formatCount, nil)
	if formatCount != 0
	{
		resize(&details.formats, formatCount)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, app.surface, &formatCount, raw_data(details.formats))
	}

	presentCount: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(device, app.surface, &presentCount, nil)
	if presentCount != 0
	{
		resize(&details.presentModes, presentCount)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, app.surface, &presentCount, raw_data(details.presentModes))
	}

	
	
	return details
}

choose_swap_surface_format :: proc(formats: ^[dynamic]vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR
{
	for f in formats
	{
		if f.format == .B8G8R8_SRGB && f.colorSpace == .SRGB_NONLINEAR
		{
			return f
		}
	}

	// Return the first format if we didnt find a suitable one
	return formats[0]
}

choose_swap_present_mode :: proc(modes: ^[dynamic]vk.PresentModeKHR) -> vk.PresentModeKHR
{
	for mode in modes
	{
		if mode == .MAILBOX
		{
			return mode
		}
	}
	
	return .FIFO
}

choose_swap_extent :: proc(capabilities: ^vk.SurfaceCapabilitiesKHR) -> vk.Extent2D
{
	if capabilities.currentExtent.width != max(u32)
	{
		return capabilities.currentExtent
	}
	else
	{
		w, h := glfw.GetFramebufferSize(app.window)
		
		extent: vk.Extent2D
		extent.width  = math.clamp(u32(w), capabilities.minImageExtent.width,  capabilities.maxImageExtent.width)
		extent.height = math.clamp(u32(h), capabilities.minImageExtent.height, capabilities.maxImageExtent.height)
		
		return extent
	}
}

is_family_indices_complete :: proc(indices: ^QueueFamilyIndices) -> bool
{
	if indices.graphicsFamily != nil && indices.presentFamily != nil
	{
		return true
	}
	else
	{
		return false
	}
}

find_queue_families :: proc(device: vk.PhysicalDevice) -> QueueFamilyIndices
{
	indices: QueueFamilyIndices
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)
	families := make([]vk.QueueFamilyProperties, count)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(families))

	for fam, i in families
	{
		if .GRAPHICS in fam.queueFlags
		{
			indices.graphicsFamily = u32(i)
		}

		presentSupport: b32 = false
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), app.surface, &presentSupport)
		if presentSupport
		{
			indices.presentFamily = u32(i)
		}

		if is_family_indices_complete(&indices)
		{
			break
		}
	}
	
	return indices
}

populate_debug_messenger_create_info :: proc(createInfo: ^vk.DebugUtilsMessengerCreateInfoEXT)
{
	createInfo.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
	createInfo.messageSeverity = {.VERBOSE, .WARNING, .ERROR}
	createInfo.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
	createInfo.pfnUserCallback = debug_callback
}

setup_debug_messenger :: proc()
{
	if !ENABLE_VALIDATION_LAYERS do return

	createInfo: vk.DebugUtilsMessengerCreateInfoEXT
	populate_debug_messenger_create_info(&createInfo)

	result := vk.CreateDebugUtilsMessengerEXT(app.instance, &createInfo, nil, &app.debugMessenger)
	if result != .SUCCESS
	{
		fmt.panicf("Failed to create debug messenger")
	}
}

debug_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT, messageTypes: 
	vk.DebugUtilsMessageTypeFlagsEXT, pCallbackData: 
	^vk.DebugUtilsMessengerCallbackDataEXT, pUserData: rawptr) -> b32
{
	context = runtime.default_context()
	fmt.printf("validation layer: %s \n", pCallbackData.pMessage)
	return false
}

check_validation_layer_support :: proc() -> bool
{
	count: u32
	vk.EnumerateInstanceLayerProperties(&count, nil)

	layers := make([]vk.LayerProperties, count)
	vk.EnumerateInstanceLayerProperties(&count, raw_data(layers))

	builder: strings.Builder
	for layerName in validationLayers
	{
		layerFound := false
		for &layerProp in layers
		{
			bytes := bytes.trim_null(layerProp.layerName[:])
			strings.write_bytes(&builder, bytes)
			name := strings.to_string(builder)
			
			if strings.compare(string(layerName), name) == 0
			{
				layerFound = true
				break
			}
			
			strings.builder_reset(&builder)
		}

		if !layerFound
		{
			fmt.println("not found", layerName)
			return false
		}
	}

	return true
}

get_required_extensions :: proc() -> []cstring
{
	glfwExts := glfw.GetRequiredInstanceExtensions()
	count := len(glfwExts) if !ENABLE_VALIDATION_LAYERS else len(glfwExts) + 1
	extensions := make_slice([]cstring, count)

	for i in 0..<len(glfwExts)
	{
		extensions[i] = glfwExts[i]
	}
	
	if ENABLE_VALIDATION_LAYERS
	{
		extensions[count - 1] = vk.EXT_DEBUG_UTILS_EXTENSION_NAME	
	}

	return extensions
}

main :: proc()
{
	allocator := mem.Tracking_Allocator{}
	mem.tracking_allocator_init(&allocator, context.allocator)
	context.allocator = mem.tracking_allocator(&allocator)
	
	fmt.println("")
	context.logger = log.create_console_logger(log.Level.Warning)
	init_window()
	init_vulkan()
	main_loop()
	cleanup()
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int)
{
 	if key == glfw.KEY_ESCAPE && action == glfw.PRESS	
 	{
 		glfw.SetWindowShouldClose(window, true)
 	}

}

// ------------------------------ MODEL LOADING ----------------------------------------------\\

load_model :: proc(name: cstring)
{
	data, result := cgltf.parse_file({}, name)
	if result != .success  
	{
		fmt.panicf("Failed to load model file: %s", name)
	}

	result = cgltf.load_buffers({}, data, name)
	if result != .success
	{
		fmt.panicf("Failed to load model %s buffers with error: %v", name, result)
	}
	defer cgltf.free(data)
	
	// Load positions
	pos     := parse_mesh_data(&data.accessors[0], Vec3)
	nrm     := parse_mesh_data(&data.accessors[1], Vec3)
	uv      := parse_mesh_data(&data.accessors[2], Vec2)
	indices := parse_mesh_data(&data.accessors[3], u16)

	vertices := make([]Vertex, len(pos))
	for &v, i in vertices
	{
		v.pos = pos[i]
		v.texCoord = uv[i]
		v.col = 1
	}

	app.indices = indices
	app.vertices = vertices
}

parse_mesh_data :: proc(acc: ^cgltf.accessor, $T: typeid) -> []T
{
	slice := make([]T, acc.count)
	size  := acc.count * acc.stride
	data  := acc.buffer_view.buffer.data
	
	src := uintptr(data) + uintptr(acc.buffer_view.offset)
	mem.copy(&slice[0], rawptr(src), int(acc.buffer_view.size))

	return slice
}


// ------------------------------               ----------------------------------------------\\

// ------------------------------ EXTRA CODE ------------------------------------------------ \\
IDENTITY      :: linalg.MATRIX4F32_IDENTITY
rotate_mat    :: linalg.matrix4_rotate_f32
translate_mat :: linalg.matrix4_translate_f32
scale_mat     :: linalg.matrix4_scale_f32

shouldPrintFps := true
lastFPSUpdateTime: f64 
fps: u32


Input :: struct
{
	move: Vec3,
}
input: Input

init_game :: proc()
{
	camera.position = {0, 0, -1}
	camera.speed = 2.5
}

update_input :: proc()
{
	velocity := 1 * app.dt
	if glfw.GetKey(app.window, glfw.KEY_W) != 0 do input.move.z += 1
	if glfw.GetKey(app.window, glfw.KEY_S) != 0 do input.move.z -= 1
	if glfw.GetKey(app.window, glfw.KEY_D) != 0 do input.move.x += 1
	if glfw.GetKey(app.window, glfw.KEY_A) != 0 do input.move.x -= 1
	
	if glfw.GetKey(app.window, glfw.KEY_E) != 0 do input.move.y += 1
	if glfw.GetKey(app.window, glfw.KEY_Q) != 0 do input.move.y -= 1
}

reset_input :: proc()
{
	input.move = 0
}

Camera :: struct
{
	position: Vec3,
	speed:    f32,
}
camera: Camera 

move_camera :: proc()
{
	camera.position += input.move * camera.speed * app.dt
}

update_fps :: proc()
{
	if !shouldPrintFps	
	{
		return
	}

	fps += 1
	if glfw.GetTime() >= lastFPSUpdateTime + 1
	{
		builder: strings.Builder
		strings.write_uint(&builder, uint(fps))
		str := strings.to_cstring(&builder)
		glfw.SetWindowTitle(app.window, str)
	
		// fmt.println("FPS:", fps)
		lastFPSUpdateTime = glfw.GetTime()
		fps = 0
	}
}

