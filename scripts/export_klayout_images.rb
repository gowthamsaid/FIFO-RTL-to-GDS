# Export authentic full-layer KLayout views of both routed GDSII files.
# Run via: xvfb-run -a klayout -z -r scripts/export_klayout_images.rb
# Requires KLayout with Ruby scripting support.
require "fileutils"

designs = [
  ["fifo_8x16", 1280, 1280],
  ["fifo_32x32", 1536, 1152]
]

mw = RBA::Application.instance.main_window
raise "KLayout main window unavailable; use -z (not -b/-zz)" if mw.nil?

FileUtils.mkdir_p("docs/images")

designs.each do |name, width, height|
  gds = File.expand_path("layout/#{name}/#{name}.gds")
  output = File.expand_path("docs/images/#{name}_klayout.png")
  raise "Missing original GDSII: #{gds}" unless File.file?(gds)

  mw.load_layout(gds, 1)
  view = mw.current_view
  raise "Unable to open GDSII in KLayout: #{name}" if view.nil?
  view.max_hier
  view.zoom_fit
  view.save_image(output, width, height)

  raise "Image missing: #{output}" unless File.file?(output)
  raise "Image unexpectedly small: #{output}" if File.size(output) < 20_000
  puts "#{name}: KLayout rendered #{width}x#{height} (#{File.size(output)} bytes)"
end
