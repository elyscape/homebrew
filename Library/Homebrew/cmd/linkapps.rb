# Links any Applications (.app) found in installed prefixes to /Applications
require "keg"
require "formula"
require "tempfile"

module Homebrew
  def linkapps
    target_dir = ARGV.include?("--local") ? File.expand_path("~/Applications") : "/Applications"

    unless File.exist? target_dir
      opoo "#{target_dir} does not exist, stopping."
      puts "Run `mkdir #{target_dir}` first."
      exit 1
    end

    check_applinks

    if ARGV.named.empty?
      kegs = Formula.racks.map do |rack|
        keg = rack.subdirs.map { |d| Keg.new(d) }
        next if keg.empty?
        keg.detect(&:linked?) || keg.max { |a, b| a.version <=> b.version }
      end
    else
      kegs = ARGV.kegs
    end

    kegs.each do |keg|
      keg.apps.each do |app|
        puts "Linking #{app} to #{HOMEBREW_APPLINKS}."
        target_link = "{HOMEBREW_APPLINKS}/#{app.basename}"

        if File.exist?(target_link) && !File.symlink?(target_link)
          onoe "#{target_link} already exists, skipping."
          next
        end

        unless system "ln", "-sf", app, HOMEBREW_APPLINKS
          onoe "Could not create symlink #{target_link}, skipping."
          next
        end

        puts "Creating alias for #{app} in #{target_dir}."
        target_alias = "#{target_dir}/#{app.basename}"

        if File.exist?(target_alias)
          unless check_alias(target_alias)
            onoe "#{target_alias} already exists, skipping."
          end
          next
        end

        create_alias(app.basename, target_dir)
      end
    end
  end

  def check_applinks
    FileUtils.mkdir_p HOMEBREW_APPLINKS unless File.exist? HOMEBREW_APPLINKS
  rescue
    raise <<-EOS.undent
      Could not create #{HOMEBREW_APPLINKS}
      Check you have permission to write to #{HOMEBREW_APPLINKS.parent}
    EOS
  end

  def check_alias(path)
    script = <<-EOS.undent
      tell application "Finder"
        set posix_shortcut to POSIX file "#{path}"
        set shortcut to item (posix_shortcut as text)
        class of shortcut
      end tell
    EOS
    script_file = Tempfile.new('check_alias')
    begin
      script_file.write(script)
      script_file.flush

      return `osascript #{script_file.path}`.chomp == "alias file"
    ensure
      script_file.close!
    end
  end

  def create_alias(app, target_dir)
    script = <<-EOS.undent
      tell application "Finder"
        set posix_applinks to POSIX file "#{HOMEBREW_APPLINKS}"
        set applinks to item (posix_applinks as text)
        set target_app to item "#{app}" of applinks

        set posix_apps to POSIX file "#{target_dir}"
        set apps to item (posix_apps as text)

        make new alias at apps to target_app
      end tell
    EOS
    script_file = Tempfile.new('create_alias')
    begin
      script_file.write(script)
      script_file.flush

      system "osascript", script_file.path
    ensure
      script_file.close!
    end
  end
end
