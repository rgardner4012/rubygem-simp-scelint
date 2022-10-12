# frozen_string_literal: true

require 'yaml'
require 'json'
require 'deep_merge'

require 'scelint/version'

module Scelint
  class Error < StandardError; end

  # Checks SCE data in the specified directories
  # @example Look for data in the current directory (the default)
  #    lint = Scelint::Lint.new()
  # @example Look for data in `/path/to/module`
  #    lint = Scelint::Lint.new('/path/to/module')
  # @example Look for data in all modules in the current directory
  #    lint = Scelint::Lint.new(Dir.glob('*'))
  class Lint
    def initialize(paths = ['.'])
      @data = {}
      @errors = []
      @warnings = []

      merged_data = {}

      paths.each do |path|
        if File.directory?(path)
          [
            'SIMP/compliance_profiles',
            'simp/compliance_profiles',
          ].each do |dir|
            ['yaml', 'json'].each do |type|
              Dir.glob("#{path}/#{dir}/**/*.#{type}").each do |file|
                this_file = parse(file)
                next if this_file.nil?
                @data[file] = this_file
                merged_data = merged_data.deep_merge!(@data[file])
              end
            end
          end
        elsif File.exist?(path)
          this_file = parse(path)
          @data[path] = this_file unless this_file.nil?
        else
          raise "Can't find path '#{path}'"
        end
      end

      return nil if @data.empty?

      @data['merged data'] = merged_data

      @data.each do |file, data|
        lint(file, data)
      end

      validate

      @data # rubocop:disable Lint/Void
    end

    def parse(file)
      return @data[file] if @data[file]

      type = case file
             when %r{\.yaml$}
               'yaml'
             when %r{\.json$}
               'json'
             else
               @errors << "#{file}: Failed to determine file type"
               return nil
             end
      begin
        return YAML.safe_load(File.read(file)) if type == 'yaml'
        return JSON.parse(File.read(file)) if type == 'json'
      rescue => e
        @errors << "#{file}: Failed to parse file: #{e.message}"
      end

      nil
    end

    def files
      @data.keys - ['merged data']
    end

    attr_reader :warnings

    attr_reader :errors

    def check_version(file, data)
      @errors << "#{file}: version check failed" unless data['version'] == '2.0.0'
    end

    def check_keys(file, data)
      ok = [
        'version',
        'profiles',
        'ce',
        'checks',
        'controls',
      ]

      data.each_key do |key|
        @warnings << "#{file}: unexpected key '#{key}'" unless ok.include?(key)
      end
    end

    def check_title(file, data)
      @warnings << "#{file}: bad title '#{data}'" unless data.is_a?(String)
    end

    def check_description(file, data)
      @warnings << "#{file}: bad description '#{data}'" unless data.is_a?(String)
    end

    def check_controls(file, data)
      if data.is_a?(Hash)
        data.each do |key, value|
          @warnings << "#{file}: bad control '#{key}'" unless key.is_a?(String) && value # Should be truthy
        end
      else
        @warnings << "#{file}: bad controls '#{data}'"
      end
    end

    def check_profile_ces(file, data)
      if data.is_a?(Hash)
        data.each do |key, value|
          @warnings << "#{file}: bad ce '#{key}'" unless key.is_a?(String) && value.is_a?(TrueClass)
        end
      else
        @warnings << "#{file}: bad ces '#{data}'"
      end
    end

    def check_profile_checks(file, data)
      if data.is_a?(Hash)
        data.each do |key, value|
          @warnings << "#{file}: bad check '#{key}'" unless key.is_a?(String) && value.is_a?(TrueClass)
        end
      else
        @warnings << "#{file}: bad checks '#{data}'"
      end
    end

    def check_confine(file, data)
      @warnings << "#{file}: bad confine '#{data}'" unless data.is_a?(Hash)
    end

    def check_identifiers(file, data)
      if data.is_a?(Hash)
        data.each do |key, value|
          if key.is_a?(String) && value.is_a?(Array)
            value.each do |identifier|
              @warnings << "#{file}: bad identifier '#{identifier}'" unless identifier.is_a?(String)
            end
          else
            @warnings << "#{file}: bad identifier '#{key}'"
          end
        end
      else
        @warnings << "#{file}: bad identifiers '#{data}'"
      end
    end

    def check_oval_ids(file, data)
      if data.is_a?(Array)
        data.each do |key|
          @warnings << "#{file}: bad oval-id '#{key}'" unless key.is_a?(String)
        end
      else
        @warnings << "#{file}: bad oval-ids '#{data}'"
      end
    end

    def check_imported_data(file, data)
      ok = ['checktext', 'fixtext']

      data.each do |key, value|
        @warnings << "#{file}: unexpected key '#{key}'" unless ok.include?(key)

        @warnings << "#{file} (key '#{key}'): bad data '#{value}'" unless value.is_a?(String)
      end
    end

    def check_profiles(file, data)
      ok = [
        'title',
        'description',
        'controls',
        'ces',
        'checks',
        'confine',
      ]

      data.each do |profile, value|
        value.each_key do |key|
          @warnings << "#{file} (profile '#{profile}'): unexpected key '#{key}'" unless ok.include?(key)
        end

        check_title(file, value['title']) unless value['title'].nil?
        check_description(file, value['description']) unless value['description'].nil?
        check_controls(file, value['controls']) unless value['controls'].nil?
        check_profile_ces(file, value['ces']) unless value['ces'].nil?
        check_profile_checks(file, value['checks']) unless value['checks'].nil?
        check_confine(file, value['confine']) unless value['confine'].nil?
      end
    end

    def check_ce(file, data)
      ok = [
        'title',
        'description',
        'controls',
        'identifiers',
        'oval-ids',
        'confine',
        'imported_data',
        'notes',
      ]

      data.each do |ce, value|
        value.each_key do |key|
          @warnings << "#{file} (CE '#{ce}'): unexpected key '#{key}'" unless ok.include?(key)
        end

        check_title(file, value['title']) unless value['title'].nil?
        check_description(file, value['description']) unless value['description'].nil?
        check_controls(file, value['controls']) unless value['controls'].nil?
        check_identifiers(file, value['identifiers']) unless value['identifiers'].nil?
        check_oval_ids(file, value['oval-ids']) unless value['oval-ids'].nil?
        check_confine(file, value['confine']) unless value['confine'].nil?
        check_imported_data(file, value['imported_data']) unless value['imported_data'].nil?
      end
    end

    def check_type(file, check, data)
      @errors << "#{file} (check '#{check}'): unknown type '#{data}'" unless data == 'puppet-class-parameter'
    end

    def check_parameter(file, check, parameter)
      @errors << "#{file} (check '#{check}'): invalid parameter '#{parameter}'" unless parameter.is_a?(String) && !parameter.empty?
    end

    def check_remediation(file, check, remediation_section)
      reason_ok = [
        'reason',
      ]

      risk_ok = [
        'level',
        'reason',
      ]

      if remediation_section.is_a?(Hash)
        remediation_section.each do |section, value|
          case section
          when 'scan-false-positive', 'disabled'
            value.each do |reason|
              # If the element in the remediation section isn't a hash, it is incorrect.
              if reason.is_a?(Hash)
                # Check for unknown elements and warn the user rather than failing
                (reason.keys - reason_ok).each do |unknown_element|
                  @warnings << "#{file} (check '#{check}'): Unknown element #{unknown_element} in remediation section #{section}"
                end
                @errors << "#{file} (check '#{check}'): malformed remediation section #{section}, must be an array of reason hashes." unless reason['reason'].is_a?(String)
              else
                @errors << "#{file} (check '#{check}'): malformed remediation section #{section}, must be an array of reason hashes."
              end
            end
          when 'risk'
            value.each do |risk|
              # If the element in the remediation section isn't a hash, it is incorrect.
              if risk.is_a?(Hash)
                # Check for unknown elements and warn the user rather than failing
                (risk.keys - risk_ok).each do |unknown_element|
                  @warnings << "#{file} (check '#{check}'): Unknown element #{unknown_element} in remediation section #{section}"
                end
                # Since reasons are optional here, we won't be checking for those

                @errors << "#{file} (check '#{check}'): malformed remediation section #{section}, must be an array of hashes containing levels and reasons." unless risk['level'].is_a?(Integer)
              else
                @errors << "#{file} (check '#{check}'): malformed remediation section #{section}, must be an array of hashes containing levels and reasons."
              end
            end
          else
            @warnings << "#{file} (check '#{check}'): #{section} is not a recognized section within the remediation section"
          end
        end
      else
        @errors << "#{file} (check '#{check}'): malformed remediation section, expecting a hash."
      end
    end

    def check_value(_file, _check, _value)
      # value could be anything
      true
    end

    def check_settings(file, check, data)
      ok = ['parameter', 'value']

      if data.nil?
        @errors << "#{file} (check '#{check}'): missing settings"
        return false
      end

      if data.key?('parameter')
        check_parameter(file, check, data['parameter'])
      else
        @errors << "#{file} (check '#{check}'): missing key 'parameter'"
      end

      if data.key?('value')
        check_value(file, check, data['value'])
      else
        @errors << "#{file} (check '#{check}'): missing key 'value'"
      end

      data.each_key do |key|
        @warnings << "#{file} (check '#{check}'): unexpected key '#{key}'" unless ok.include?(key)
      end
    end

    def check_check_ces(file, data)
      @warnings << "#{file}: bad ces '#{data}'" unless data.is_a?(Array)

      data.each do |key|
        @warnings << "#{file}: bad ce '#{key}'" unless key.is_a?(String)
      end
    end

    def check_checks(file, data)
      ok = [
        'type',
        'settings',
        'controls',
        'identifiers',
        'oval-ids',
        'ces',
        'confine',
        'remediation',
      ]

      data.each do |check, value|
        if value.nil?
          @warnings << "#{file} (check '#{check}'): empty value"
          next
        end

        if value.is_a?(Hash)
          value.each_key do |key|
            @warnings << "#{file} (check '#{check}'): unexpected key '#{key}'" unless ok.include?(key)
          end
        else
          @errors << "#{file} (check '#{check}'): contains something other than a hash, this is most likely caused by a missing note or ce element under the check"
        end

        check_type(file, check, value['type']) if value['type'] || file == 'merged data'
        check_settings(file, check, value['settings']) if value['settings'] || file == 'merged data'
        unless value['remediation'].nil?
          check_remediation(file, check, value['remediation']) if value['remediation']
        end
        check_controls(file, value['controls']) unless value['controls'].nil?
        check_identifiers(file, value['identifiers']) unless value['identifiers'].nil?
        check_oval_ids(file, value['oval-ids']) unless value['oval-ids'].nil?
        check_check_ces(file, value['ces']) unless value['ces'].nil?
        check_confine(file, value['confine']) unless value['confine'].nil?
      end
    end

    def profiles
      return @profiles unless @profiles.nil?

      return nil unless @data.key?('merged data')
      return nil unless @data['merged data']['profiles'].is_a?(Hash)

      @profiles = @data['merged data']['profiles'].keys
    end

    def confines
      return @confines unless @confines.nil?

      confine = {}

      @data.each do |key, value|
        next if key == 'merged data'
        next unless value.is_a?(Hash)

        ['profiles', 'ce', 'checks'].each do |type|
          next unless value.key?(type)
          next unless value[type].is_a?(Hash)

          value[type].each do |_k, v|
            next unless v.is_a?(Hash)
            confine = confine.merge(v['confine']) if v.key?('confine')
          end
        end
      end

      @confines = []
      index = 0
      max_count = 1
      confine.each { |_key, value| max_count *= Array(value).size }

      confine.each do |key, value|
        (index..(max_count - 1)).each do |i|
          @confines[i] ||= {}
          @confines[i][key] = Array(value)[i % Array(value).size]
        end
      end

      @confines
    end

    def apply_confinement(file, data, confine)
      return data unless data.is_a?(Hash)

      class << self
        def should_delete(file, key, specification, confine)
          return false unless specification.key?('confine')

          unless specification['confine'].is_a?(Hash)
            @warnings << "#{file}: 'confine' is not a Hash in key #{key}"
            return false
          end

          specification['confine'].each do |confinement_setting, confinement_value|
            return true unless confine.is_a?(Hash)
            return true unless confine.key?(confinement_setting)
            Array(confine[confinement_setting]).each do |value|
              return false if Array(confinement_value).include?(value)
            end
          end

          true
        end
      end

      value = Marshal.load(Marshal.dump(data))
      value.delete_if { |key, specification| should_delete(file, key, specification, confine) }

      value
    end

    def compile(profile, confine = nil)
      merged_data = {}

      # Pass 1: Merge everything with confined values removed.
      @data.each do |file, data|
        next if file == 'merged data'
        data.each do |key, value|
          confined_value = apply_confinement(file, value, confine)

          unless confined_value.is_a?(Hash)
            if merged_data.key?(key)
              @warnings << "#{file} #{confine.nil? ? '(no confinement data)' : "(confined: #{confine})"}: key #{key} redefined (previous value: #{merged_data[key]}, new value: #{confined_value})" unless key == 'version'
            end

            merged_data[key] = confined_value
            next
          end

          merged_data[key] ||= {}
          confined_value.each do |k, v|
            merged_data[key][k] ||= {}
            merged_data[key][k] = merged_data[key][k].deep_merge!(v, { knockout_prefix: '--' })
          end
        end
      end

      # Pass 2: Build a mapping of all of the checks we found.
      check_map = {
        'checks'   => {},
        'controls' => {},
        'ces'      => {},
      }

      merged_data['checks']&.each do |check_name, specification|
        unless specification['type'] == 'puppet-class-parameter'
          @warnings << "check #{check_name} #{confine.nil? ? '(no confinement data)' : "(confined: #{confine})"}: Not a Puppet parameter"
          next
        end

        unless specification['settings'].is_a?(Hash)
          @warnings << "check #{check_name} #{confine.nil? ? '(no confinement data)' : "(confined: #{confine})"}: Missing required 'settings' Hash"
          next
        end

        unless specification['settings'].key?('parameter') && specification['settings']['parameter'].is_a?(String)
          @warnings << "check #{check_name} #{confine.nil? ? '(no confinement data)' : "(confined: #{confine})"}: Missing required key 'parameter' or wrong data type"
          next
        end

        unless specification['settings'].key?('value')
          @warnings << "check #{check_name} #{confine.nil? ? '(no confinement data)' : "(confined: #{confine})"}: Missing required key 'value' for parameter #{specification['settings']['parameter']}"
          next
        end

        check_map['checks'][check_name] = [specification]

        specification['controls']&.each do |control_name, v|
          next unless v
          check_map['controls'][control_name] ||= []
          check_map['controls'][control_name] << specification
        end

        specification['ces']&.each do |ce_name|
          next unless merged_data['ce']&.key?(ce_name)

          check_map['ces'][ce_name] ||= []
          check_map['ces'][ce_name] << specification

          merged_data['ce'][ce_name]['controls']&.each do |control_name, value|
            next unless value

            check_map['controls'][control_name] ||= []
            check_map['controls'][control_name] << specification
          end
        end
      end

      # Pass 3: Extract the relevant Hiera values.
      hiera_spec = []
      info = merged_data['profiles'][profile] || {}

      ['checks', 'controls', 'ces'].each do |map_type|
        info[map_type]&.each do |key, value|
          next unless value
          next unless check_map[map_type]&.key?(key)
          hiera_spec += check_map[map_type][key]
        end
      end

      if hiera_spec.empty?
        @warnings << "#{profile} #{confine.nil? ? '(no confinement data)' : "(confined: #{confine})"}: No Hiera values found"
        return {}
      end

      hiera = {}

      hiera_spec.each do |spec|
        setting = spec['settings']

        if hiera.key?(setting['parameter'])
          if setting['value'].class.to_s != hiera[setting['parameter']].class.to_s
            warnings << [
              "#{profile} #{confine.nil? ? '(no confinement data)' : "(confined: #{confine})"}:  key #{setting['parameter']} type mismatch",
              "(previous value: #{hiera[setting['parameter']]} (#{hiera[setting['parameter']].class}),",
              "new value: #{setting['value']} (#{setting['value'].class})",
            ].join(' ')
            hiera[setting['parameter']] = setting['value']
            next
          end

          if setting['value'].is_a?(Hash)
            # warn "#{profile}: Merging Hash values for #{setting['parameter']}"
            hiera[setting['parameter']] = hiera[setting['parameter']].deep_merge!(setting['value'])
            next
          end

          if setting['value'].is_a?(Array)
            # warn "#{profile}: Merging Array values for #{setting['parameter']}"
            hiera[setting['parameter']] = (hiera[setting['parameter']] + setting['value']).uniq
            next
          end

          warnings << "#{profile} #{confine.nil? ? '(no confinement data)' : "(confined: #{confine})"}: key #{setting['parameter']} redefined (previous value: #{hiera[setting['parameter']]}, new value: #{setting['value']})"
        end

        hiera[setting['parameter']] = setting['value']
      end
    end

    def validate
      if profiles.nil?
        @warnings << 'No profiles found, unable to validate Hiera data'
        return nil
      end

      profiles.each do |profile|
        compile(profile)
        confines.each do |confine|
          compile(profile, confine)
        end
      end
    end

    def lint(file, data)
      check_version(file, data)
      check_keys(file, data)

      check_profiles(file, data['profiles']) if data['profiles']
      check_ce(file, data['ce']) if data['ce']
      check_checks(file, data['checks']) if data['checks']
      check_controls(file, data['controls']) if data['controls']
    rescue => e
      @errors << "#{file}: #{e.message} (not a hash?)"
    end
  end
end
