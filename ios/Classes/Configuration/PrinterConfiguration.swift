import Foundation

/// Configuration for printer connections and operations
public struct PrinterConfiguration {
    
    // MARK: - Connection Timeouts
    
    /// BLE connection timeout in seconds (default: 15.0)
    public let bleConnectionTimeout: TimeInterval
    
    /// WiFi connection timeout in seconds (default: 10.0)
    public let wifiConnectionTimeout: TimeInterval
    
    /// MFi/External Accessory connection timeout in seconds (default: 10.0)
    public let mfiConnectionTimeout: TimeInterval
    
    /// Service discovery timeout for BLE in seconds (default: 5.0)
    public let bleServiceDiscoveryTimeout: TimeInterval
    
    /// Characteristic discovery timeout for BLE in seconds (default: 3.0)
    public let bleCharacteristicDiscoveryTimeout: TimeInterval
    
    // MARK: - Data Transmission
    
    /// BLE chunk size in bytes (default: 20 for compatibility)
    public let bleChunkSize: Int
    
    /// MFi chunk size in bytes (default: 512)
    public let mfiChunkSize: Int
    
    /// WiFi chunk size in bytes (default: 1024)
    public let wifiChunkSize: Int
    
    /// Delay between chunks for BLE in seconds (default: 0.01)
    public let bleChunkDelay: TimeInterval
    
    /// Delay between chunks for MFi in seconds (default: 0.01)
    public let mfiChunkDelay: TimeInterval
    
    /// Delay between chunks for WiFi in seconds (default: 0.0)
    public let wifiChunkDelay: TimeInterval
    
    // MARK: - Retry Configuration
    
    /// Maximum retry attempts for connections (default: 3)
    public let maxConnectionRetries: Int
    
    /// Maximum retry attempts for data transmission (default: 3)
    public let maxTransmissionRetries: Int
    
    /// Retry delay base in seconds for exponential backoff (default: 1.0)
    public let retryDelayBase: TimeInterval
    
    /// Maximum retry delay in seconds (default: 5.0)
    public let maxRetryDelay: TimeInterval
    
    // MARK: - Image Processing
    
    /// Maximum image width in pixels before resizing (default: 2048)
    public let maxImageWidth: Int
    
    /// Maximum image height in pixels before resizing (default: 2048)
    public let maxImageHeight: Int
    
    /// Image compression quality (0.0 to 1.0, default: 0.8)
    public let imageCompressionQuality: CGFloat
    
    // MARK: - Initialization
    
    public init(
        bleConnectionTimeout: TimeInterval = 15.0,
        wifiConnectionTimeout: TimeInterval = 10.0,
        mfiConnectionTimeout: TimeInterval = 10.0,
        bleServiceDiscoveryTimeout: TimeInterval = 5.0,
        bleCharacteristicDiscoveryTimeout: TimeInterval = 3.0,
        bleChunkSize: Int = 20,
        mfiChunkSize: Int = 512,
        wifiChunkSize: Int = 1024,
        bleChunkDelay: TimeInterval = 0.01,
        mfiChunkDelay: TimeInterval = 0.01,
        wifiChunkDelay: TimeInterval = 0.0,
        maxConnectionRetries: Int = 3,
        maxTransmissionRetries: Int = 3,
        retryDelayBase: TimeInterval = 1.0,
        maxRetryDelay: TimeInterval = 5.0,
        maxImageWidth: Int = 2048,
        maxImageHeight: Int = 2048,
        imageCompressionQuality: CGFloat = 0.8
    ) {
        self.bleConnectionTimeout = bleConnectionTimeout
        self.wifiConnectionTimeout = wifiConnectionTimeout
        self.mfiConnectionTimeout = mfiConnectionTimeout
        self.bleServiceDiscoveryTimeout = bleServiceDiscoveryTimeout
        self.bleCharacteristicDiscoveryTimeout = bleCharacteristicDiscoveryTimeout
        self.bleChunkSize = bleChunkSize
        self.mfiChunkSize = mfiChunkSize
        self.wifiChunkSize = wifiChunkSize
        self.bleChunkDelay = bleChunkDelay
        self.mfiChunkDelay = mfiChunkDelay
        self.wifiChunkDelay = wifiChunkDelay
        self.maxConnectionRetries = maxConnectionRetries
        self.maxTransmissionRetries = maxTransmissionRetries
        self.retryDelayBase = retryDelayBase
        self.maxRetryDelay = maxRetryDelay
        self.maxImageWidth = maxImageWidth
        self.maxImageHeight = maxImageHeight
        self.imageCompressionQuality = imageCompressionQuality
    }
    
    // MARK: - Preset Configurations
    
    /// Default configuration optimized for most printers
    public static let `default` = PrinterConfiguration()
    
    /// Fast configuration for reliable connections (fewer retries, shorter timeouts)
    public static let fast = PrinterConfiguration(
        bleConnectionTimeout: 10.0,
        wifiConnectionTimeout: 5.0,
        mfiConnectionTimeout: 5.0,
        bleServiceDiscoveryTimeout: 3.0,
        bleCharacteristicDiscoveryTimeout: 2.0,
        maxConnectionRetries: 1,
        maxTransmissionRetries: 1,
        retryDelayBase: 0.5
    )
    
    /// Reliable configuration for unstable connections (more retries, longer timeouts)
    public static let reliable = PrinterConfiguration(
        bleConnectionTimeout: 20.0,
        wifiConnectionTimeout: 15.0,
        mfiConnectionTimeout: 15.0,
        bleServiceDiscoveryTimeout: 8.0,
        bleCharacteristicDiscoveryTimeout: 5.0,
        maxConnectionRetries: 5,
        maxTransmissionRetries: 5,
        retryDelayBase: 1.5,
        maxRetryDelay: 10.0
    )
    
    /// High-quality configuration for image printing (larger images, better quality)
    public static let highQuality = PrinterConfiguration(
        maxImageWidth: 4096,
        maxImageHeight: 4096,
        imageCompressionQuality: 0.95
    )
}

