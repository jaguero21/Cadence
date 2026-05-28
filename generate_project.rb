require 'xcodeproj'

PROJECT_ROOT = File.dirname(__FILE__)
PROJECT_NAME = 'Cadence'
BUNDLE_ID    = 'com.cadence.app'
TARGET_NAME  = 'Cadence'
IOS_VERSION  = '17.0'

proj = Xcodeproj::Project.new("#{PROJECT_ROOT}/#{PROJECT_NAME}.xcodeproj")

# ── Target ──────────────────────────────────────────────────────────────────
target = proj.new_target(:application, TARGET_NAME, :ios, IOS_VERSION)

# ── Main Group ──────────────────────────────────────────────────────────────
main_group = proj.main_group.new_group(TARGET_NAME, "#{PROJECT_ROOT}/#{TARGET_NAME}")

GROUPS = {
  'App'      => ["#{TARGET_NAME}/App"],
  'Models'   => ["#{TARGET_NAME}/Models"],
  'Shared'   => [
    "#{TARGET_NAME}/Shared",
    "#{TARGET_NAME}/Shared/Components",
    "#{TARGET_NAME}/Shared/Extensions",
  ],
  'Features/Dashboard'     => ["#{TARGET_NAME}/Features/Dashboard"],
  'Features/DailyLog'      => ["#{TARGET_NAME}/Features/DailyLog"],
  'Features/WeeklyReview'  => ["#{TARGET_NAME}/Features/WeeklyReview"],
  'Features/Insights'      => ["#{TARGET_NAME}/Features/Insights"],
  'Features/History'       => ["#{TARGET_NAME}/Features/History"],
  'Features/Export'        => ["#{TARGET_NAME}/Features/Export"],
  'Features/Settings'      => ["#{TARGET_NAME}/Features/Settings"],
  'Services'               => ["#{TARGET_NAME}/Services"],
}

group_map = {}

def find_or_make_group(parent, name)
  parent.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == name } ||
    parent.new_group(name)
end

GROUPS.each do |label, paths|
  parts = label.split('/')
  current = main_group
  parts.each do |part|
    current = find_or_make_group(current, part)
  end
  group_map[label] = current
  current.set_source_tree('<group>')
  current.set_path("#{PROJECT_ROOT}/#{TARGET_NAME}/#{label.gsub('Features/', 'Features/')}")
end

# ── Add Swift source files ──────────────────────────────────────────────────
sources_phase = target.source_build_phase

def add_files(project, target, group, dir_path, phase)
  return unless Dir.exist?(dir_path)
  Dir.glob("#{dir_path}/*.swift").each do |filepath|
    file_ref = group.new_reference(filepath)
    file_ref.set_source_tree('<absolute>')
    phase.add_file_reference(file_ref)
  end
end

# App — Swift files only; Info.plist is referenced via INFOPLIST_FILE build setting, not a resource
add_files(proj, target, group_map['App'], "#{PROJECT_ROOT}/#{TARGET_NAME}/App", sources_phase)

# Add Info.plist as a file reference in the group (for visibility) but NOT to any build phase
plist_ref = group_map['App'].new_reference("#{PROJECT_ROOT}/#{TARGET_NAME}/App/Info.plist")
plist_ref.set_source_tree('<absolute>')

# Models
add_files(proj, target, group_map['Models'], "#{PROJECT_ROOT}/#{TARGET_NAME}/Models", sources_phase)

# Shared
add_files(proj, target, group_map['Shared'], "#{PROJECT_ROOT}/#{TARGET_NAME}/Shared", sources_phase)
add_files(proj, target, group_map['Shared'], "#{PROJECT_ROOT}/#{TARGET_NAME}/Shared/Components", sources_phase)
add_files(proj, target, group_map['Shared'], "#{PROJECT_ROOT}/#{TARGET_NAME}/Shared/Extensions", sources_phase)

# Features
{
  'Features/Dashboard'    => 'Dashboard',
  'Features/DailyLog'     => 'DailyLog',
  'Features/WeeklyReview' => 'WeeklyReview',
  'Features/Insights'     => 'Insights',
  'Features/History'      => 'History',
  'Features/Export'       => 'Export',
  'Features/Settings'     => 'Settings',
}.each do |key, folder|
  add_files(proj, target, group_map[key], "#{PROJECT_ROOT}/#{TARGET_NAME}/Features/#{folder}", sources_phase)
end

# Services
add_files(proj, target, group_map['Services'], "#{PROJECT_ROOT}/#{TARGET_NAME}/Services", sources_phase)

# ── Build Settings ───────────────────────────────────────────────────────────
debug_config   = proj.add_build_configuration('Debug',   :debug)
release_config = proj.add_build_configuration('Release', :release)

shared_settings = {
  'PRODUCT_NAME'                      => TARGET_NAME,
  'PRODUCT_BUNDLE_IDENTIFIER'         => BUNDLE_ID,
  'IPHONEOS_DEPLOYMENT_TARGET'        => IOS_VERSION,
  'SWIFT_VERSION'                     => '5.9',
  'INFOPLIST_FILE'                    => "#{TARGET_NAME}/App/Info.plist",
  'CODE_SIGN_STYLE'                   => 'Automatic',
  'DEVELOPMENT_TEAM'                  => '',
  'TARGETED_DEVICE_FAMILY'            => '1',
  'ENABLE_PREVIEWS'                   => 'YES',
  'SWIFT_EMIT_LOC_STRINGS'            => 'YES',
}

[debug_config, release_config].each do |config|
  config.build_settings.merge!(shared_settings)
end

target.build_configurations.each do |config|
  config.build_settings.merge!(shared_settings)
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  config.build_settings['INFOPLIST_FILE'] = "#{TARGET_NAME}/App/Info.plist"
end

# ── Frameworks ───────────────────────────────────────────────────────────────
frameworks_phase = target.frameworks_build_phase

def add_framework(project, phase, name)
  ref = project.frameworks_group.new_reference("System/Library/Frameworks/#{name}.framework")
  ref.name = name
  ref.set_source_tree('SDKROOT')
  phase.add_file_reference(ref)
rescue => e
  puts "Warning adding #{name}: #{e.message}"
end

%w[SwiftUI SwiftData HealthKit PDFKit StoreKit UserNotifications Charts].each do |fw|
  add_framework(proj, frameworks_phase, fw)
end

# ── Save ─────────────────────────────────────────────────────────────────────
proj.save
puts "\n✅ #{PROJECT_NAME}.xcodeproj created successfully!"
puts "   Open with: open #{PROJECT_ROOT}/#{PROJECT_NAME}.xcodeproj"
