/* vk14probe: can DXVK run here? Checks through Wine's own Vulkan (vulkan-1.dll ->
 * winevulkan -> the host's Vulkan loader and driver), the same way DXVK will, that a
 * GPU supports Vulkan 1.4, which DXVK 3 needs (Mesa 25+, NVIDIA 575+).
 *
 *   wine vk14probe.exe     exit 0: a Vulkan 1.4 GPU was found (printed)
 *                          exit 1: no Vulkan 1.4 GPU (each GPU's version printed)
 *                          exit 2: Vulkan doesn't work at all
 *
 * Self-contained (no Vulkan headers): only the few declarations it needs.
 * Build: x86_64-w64-mingw32-gcc -O2 -o vk14probe.exe vk14probe.c */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>

#define VK_API_VERSION(major, minor) (((uint32_t)(major) << 22) | ((uint32_t)(minor) << 12))
#define VK_VERSION_MAJOR(v) ((v) >> 22)
#define VK_VERSION_MINOR(v) (((v) >> 12) & 0x3ff)
#define VK_VERSION_PATCH(v) ((v) & 0xfff)

typedef void *VkInstance, *VkPhysicalDevice;
typedef int32_t VkResult;

typedef struct
{
    uint32_t sType;  /* VK_STRUCTURE_TYPE_APPLICATION_INFO = 0 */
    const void *pNext;
    const char *pApplicationName;
    uint32_t applicationVersion;
    const char *pEngineName;
    uint32_t engineVersion;
    uint32_t apiVersion;
} VkApplicationInfo;

typedef struct
{
    uint32_t sType;  /* VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1 */
    const void *pNext;
    uint32_t flags;
    const VkApplicationInfo *pApplicationInfo;
    uint32_t enabledLayerCount;
    const char *const *ppEnabledLayerNames;
    uint32_t enabledExtensionCount;
    const char *const *ppEnabledExtensionNames;
} VkInstanceCreateInfo;

/* The start of VkPhysicalDeviceProperties; the rest (limits etc.) is left as padding. */
typedef struct
{
    uint32_t apiVersion;
    uint32_t driverVersion;
    uint32_t vendorID;
    uint32_t deviceID;
    uint32_t deviceType;
    char deviceName[256];
    uint8_t rest[4096];
} VkPhysicalDevicePropertiesStart;

typedef void (__stdcall *PFN_vkVoidFunction)(void);
typedef PFN_vkVoidFunction (__stdcall *PFN_vkGetInstanceProcAddr)(VkInstance, const char *);
typedef VkResult (__stdcall *PFN_vkCreateInstance)(const VkInstanceCreateInfo *, const void *, VkInstance *);
typedef void (__stdcall *PFN_vkDestroyInstance)(VkInstance, const void *);
typedef VkResult (__stdcall *PFN_vkEnumeratePhysicalDevices)(VkInstance, uint32_t *, VkPhysicalDevice *);
typedef void (__stdcall *PFN_vkGetPhysicalDeviceProperties)(VkPhysicalDevice, VkPhysicalDevicePropertiesStart *);

int main(void)
{
    VkApplicationInfo app = { 0, NULL, "vk14probe", 1, NULL, 0, VK_API_VERSION(1, 4) };
    VkInstanceCreateInfo info = { 1, NULL, 0, &app, 0, NULL, 0, NULL };
    PFN_vkGetInstanceProcAddr get_proc;
    PFN_vkCreateInstance create_instance;
    PFN_vkDestroyInstance destroy_instance;
    PFN_vkEnumeratePhysicalDevices enum_devices;
    PFN_vkGetPhysicalDeviceProperties get_props;
    VkPhysicalDevice devices[16];
    VkInstance instance;
    uint32_t count = 16, i;
    VkResult res;
    HMODULE vulkan;
    int found = 0;

    if (!(vulkan = LoadLibraryA( "vulkan-1.dll" )))
    {
        printf( "No vulkan-1.dll (error %lu)\n", GetLastError() );
        return 2;
    }
    get_proc = (PFN_vkGetInstanceProcAddr)GetProcAddress( vulkan, "vkGetInstanceProcAddr" );
    create_instance = get_proc ? (PFN_vkCreateInstance)get_proc( NULL, "vkCreateInstance" ) : NULL;
    if (!create_instance)
    {
        printf( "vulkan-1.dll has no vkCreateInstance\n" );
        return 2;
    }
    if ((res = create_instance( &info, NULL, &instance )))
    {
        printf( "Vulkan doesn't start here: vkCreateInstance failed, VkResult %d\n", (int)res );
        return 2;
    }
    destroy_instance = (PFN_vkDestroyInstance)get_proc( instance, "vkDestroyInstance" );
    enum_devices = (PFN_vkEnumeratePhysicalDevices)get_proc( instance, "vkEnumeratePhysicalDevices" );
    get_props = (PFN_vkGetPhysicalDeviceProperties)get_proc( instance, "vkGetPhysicalDeviceProperties" );

    if ((res = enum_devices( instance, &count, devices )) < 0 || !count)
    {
        printf( "Vulkan found no GPU (VkResult %d)\n", (int)res );
        destroy_instance( instance, NULL );
        return 2;
    }
    for (i = 0; i < count; i++)
    {
        static VkPhysicalDevicePropertiesStart props;
        BOOL ok;

        get_props( devices[i], &props );
        props.deviceName[255] = 0;
        ok = props.apiVersion >= VK_API_VERSION(1, 4);
        printf( "%s: Vulkan %u.%u.%u%s\n", props.deviceName, VK_VERSION_MAJOR(props.apiVersion),
                VK_VERSION_MINOR(props.apiVersion), VK_VERSION_PATCH(props.apiVersion),
                ok ? " (enough for DXVK)" : " (DXVK needs 1.4)" );
        if (ok) found = 1;
    }
    destroy_instance( instance, NULL );
    return found ? 0 : 1;
}
