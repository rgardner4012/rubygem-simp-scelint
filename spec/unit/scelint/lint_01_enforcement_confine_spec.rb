# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Scelint::Lint do
  def test_module
    "test_module_#{File.basename(__FILE__).split('_')[1]}"
  end

  def fixtures
    File.expand_path('../../fixtures', __dir__)
  end

  def module_path
    File.join(fixtures, 'modules', test_module)
  end

  subject(:lint) { described_class.new([module_path]) }

  context 'validating test data' do
    it 'initializes' do
      expect(lint).to be_instance_of(described_class)
    end

    it 'checks files' do
      expect(lint.files.count).to eq(3)
    end

    it 'has no errors' do
      expect(lint.errors).to eq([])
    end

    it 'has a warning' do
      expect(lint.warnings.count).to eq(1)
      expect(lint.warnings[0]).to match(%r{no confinement data.*No Hiera values found})
    end
  end
end
