package vktest

import "core:fmt"
import "core:os"
import "core:math"
import "core:log"
import "core:bytes"
import "core:strings"
import "core:c"

import "base:runtime"

import "vendor:glfw"
import vk "vendor:vulkan"

ENABLE_VALIDATION_LAYERS :: true
NULL_HANDLE :: 0

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
	window:           glfw.WindowHandle,
	instance:         vk.Instance,
	extensions:       []vk.ExtensionProperties,
	debugMessenger:   vk.DebugUtilsMessengerEXT,
	physicalDevice:   vk.PhysicalDevice,
	device:           vk.Device,
	graphicsQueue:    vk.Queue,
	presentQueue:     vk.Queue,
	surface:          vk.SurfaceKHR,
	swapchain:        vk.SwapchainKHR,
	swapImages:       [dynamic]vk.Image,
	swapImageFormat:  vk.Format,
	swapImageViews:   [dynamic]vk.ImageView,
	swapFramebuffers: [dynamic]vk.Framebuffer,
	swapExtent:       vk.Extent2D,
	pipelineLayout:   vk.PipelineLayout,
	renderPass:       vk.RenderPass,
	graphicsPipeline: vk.Pipeline,
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

init_window :: proc()
{
	initOk := glfw.Init()
	if !initOk
	{
		desc, err := glfw.GetError()
		fmt.panicf("Could not init glfw: ", desc, err)
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE,  glfw.FALSE)
	app.window = glfw.CreateWindow(winWidth, winHeight, "VKTEST", nil, nil)
	glfw.SetKeyCallback(app.window, key_callback)
	glfw.MakeContextCurrent(app.window)
}


main_loop :: proc()
{
	for !glfw.WindowShouldClose(app.window)
	{
		glfw.PollEvents()
	}

}

cleanup :: proc()
{
	for buffer in app.swapFramebuffers
	{
		vk.DestroyFramebuffer(app.device, buffer, nil)
	}
	
	vk.DestroyPipeline(app.device, app.graphicsPipeline, nil)
	vk.DestroyPipelineLayout(app.device, app.pipelineLayout, nil)
	vk.DestroyRenderPass(app.device, app.renderPass, nil)
	
	for view in app.swapImageViews
	{
		vk.DestroyImageView(app.device, view, nil)
	}
	
	vk.DestroySwapchainKHR(app.device, app.swapchain, nil)
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
	create_graphics_pipeline()
	create_framebuffers()
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

	for dev in devices
	{
		if is_device_suitable(dev)
		{
			app.physicalDevice = dev
			break
		}
	}

	if app.physicalDevice == nil
	{
		fmt.panicf("Failed to find suitable GPU")
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
		createInfo: vk.ImageViewCreateInfo
		createInfo.sType = .IMAGE_VIEW_CREATE_INFO
		createInfo.image = app.swapImages[i]
		createInfo.viewType = .D2
		createInfo.format = app.swapImageFormat
		
		createInfo.components.r = vk.ComponentSwizzle.IDENTITY
		createInfo.components.g = vk.ComponentSwizzle.IDENTITY
		createInfo.components.b = vk.ComponentSwizzle.IDENTITY
		createInfo.components.a = vk.ComponentSwizzle.IDENTITY

		createInfo.subresourceRange.aspectMask = {.COLOR}
		createInfo.subresourceRange.baseMipLevel = 0
		createInfo.subresourceRange.levelCount = 1	
		createInfo.subresourceRange.baseArrayLayer = 0
		createInfo.subresourceRange.layerCount = 1
		
		if vk.CreateImageView(app.device, &createInfo, nil, &app.swapImageViews[i]) != .SUCCESS
		{
			fmt.panicf("Failed to create image view")
		}
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

	subpass: vk.SubpassDescription
	subpass.pipelineBindPoint = .GRAPHICS
	subpass.colorAttachmentCount = 1
	subpass.pColorAttachments = &colorAttachmentRef
	
	renderPassInfo: vk.RenderPassCreateInfo
	renderPassInfo.sType = .RENDER_PASS_CREATE_INFO
	renderPassInfo.attachmentCount = 1
	renderPassInfo.pAttachments = &colorAttachment
	renderPassInfo.subpassCount = 1
	renderPassInfo.pSubpasses = &subpass

	if vk.CreateRenderPass(app.device, &renderPassInfo, nil, &app.renderPass) != .SUCCESS
	{
		fmt.panicf("Failed to create render pass")
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
	
	// NOTE: Do i need to specify all things ?
	vertInputInfo: vk.PipelineVertexInputStateCreateInfo
	vertInputInfo.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO

	inputAssembly: vk.PipelineInputAssemblyStateCreateInfo
	inputAssembly.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
	inputAssembly.topology = .TRIANGLE_LIST
	inputAssembly.primitiveRestartEnable = false

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
	rasterizer.cullMode = {.BACK}
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
	// colorBlendAttachment.colorWriteMask = {.R, .G, .B, .A}
	// colorBlendAttachment.srcColorBlendFactor = .ONE
	// colorBlendAttachment.dstColorBlendFactor = .ZERO
	// colorBlendAttachment.colorBlendOp = .ADD
	// colorBlendAttachment.srcAlphaBlendFactor = .ONE
	// colorBlendAttachment.dstAlphaBlendFactor = .ZERO
	// colorBlendAttachment.alphaBlendOp = .ADD

	colorBlendInfo: vk.PipelineColorBlendStateCreateInfo
	colorBlendInfo.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
	colorBlendInfo.logicOpEnable = false
	colorBlendInfo.logicOp = .COPY
	colorBlendInfo.attachmentCount = 1
	colorBlendInfo.pAttachments = &colorBlendAttachment

	pipeLayoutInfo: vk.PipelineLayoutCreateInfo
	pipeLayoutInfo.sType = .PIPELINE_LAYOUT_CREATE_INFO
	if vk.CreatePipelineLayout(app.device, &pipeLayoutInfo, nil, &app.pipelineLayout) != .SUCCESS
	{
		fmt.panicf("Could not create pipeline layout")
	}
	
	// NOTE: Does this work when it goes out of scope ?
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
		attachments: []vk.ImageView = {view}

		framebufferInfo: vk.FramebufferCreateInfo
		framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
		framebufferInfo.renderPass = app.renderPass
		framebufferInfo.attachmentCount = 1
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

	fmt.printfln("%s", props.deviceName)

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
	return is_family_indices_complete(&indices) && extSupported && isSwapchainAdequate
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