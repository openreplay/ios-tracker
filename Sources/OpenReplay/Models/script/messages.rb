message 92, 'MobileMetadata' do
    uint 'Timestamp'
    uint 'Length'
    string 'Key'
    string 'Value'
end

message 93, 'MobileEvent' do
    uint 'Timestamp'
    uint 'Length'
    string 'Name'
    string 'Payload'
end

message 94, 'MobileUserID' do
    uint 'Timestamp'
    uint 'Length'
    string 'ID'
end

message 95, 'MobileUserAnonymousID' do
    uint 'Timestamp'
    uint 'Length'
    string 'ID'
end

message 96, 'MobileScreenChanges' do
    uint 'Timestamp'
    uint 'Length'
    uint 'X'
    uint 'Y'
    uint 'Width'
    uint 'Height'
end

message 97, 'MobileCrash' do
    uint 'Timestamp'
    uint 'Length'
    string 'Name'
    string 'Reason'
    string 'Stacktrace'
end

message 98, 'MobileViewComponentEvent' do
    uint 'Timestamp'
    uint 'Length'
    string 'ScreenName'
    string 'ViewName'
    boolean 'Visible'
end

message 100, 'MobileClickEvent' do
    uint 'Timestamp'
    uint 'Length'
    string 'Label'
    uint 'X'
    uint 'Y'
end

message 101, 'MobileInputEvent' do
    uint 'Timestamp'
    uint 'Length'
    string 'Value'
    boolean 'ValueMasked'
    string 'Label'
end

=begin
Name/Value may be :
"physicalMemory": Total memory in bytes
"processorCount": Total processors in device
"activeProcessorCount": Number of currently used processors
"systemUptime": Elapsed time (in seconds) since last boot
"isLowPowerModeEnabled": Possible values (1 or 0)
"thermalState": Possible values (0:nominal 1:fair 2:serious 3:critical)
"batteryLevel": Possible values (0 .. 100)
"batteryState": Possible values (0:unknown 1:unplugged 2:charging 3:full)
"orientation": Possible values (0unknown 1:portrait 2:portraitUpsideDown 3:landscapeLeft 4:landscapeRight 5:faceUp 6:faceDown)
"mainThreadCPU": Possible values (0 .. 100)
"memoryUsage": Used memory in bytes
"fps": Frames per second
=end
message 102, 'MobilePerformanceEvent', :replayer => true do
  uint 'Timestamp'
  uint 'Length'
  string 'Name'
  uint 'Value'
end

message 103, 'MobileLog' do
  uint 'Timestamp'
  uint 'Length'
  string 'Severity' # Possible values ("info", "error")
  string 'Content'
end

message 104, 'MobileInternalError' do
  uint 'Timestamp'
  uint 'Length'
  string 'Content'
end

message 105, 'MobileNetworkCall' do
   uint 'Timestamp'
   uint 'Length'
   string 'Type'
   string 'Method'
   string 'URL'
   string 'Request'
   string 'Response'
   uint 'Status'
   uint 'Duration'
end

message 106, 'MobileSwipeEvent' do
    uint 'Timestamp'
    uint 'Length'
    string 'Label'
    uint 'X'
    uint 'Y'
    string 'Direction'
end

message 107, 'MobileBatchMeta' do
    uint 'Timestamp'
    uint 'Length'
    uint 'FirstIndex'
end


message 109, 'GraphQL' do
    uint 'Timestamp'
    uint 'Length'
    string 'OperationKind'
    string 'OperationName'
    string 'Variables'
    string 'Response'
    uint 'Duration'
end


=begin

EXTENSIONS AND PLUGINS
+ ported from web
=end
