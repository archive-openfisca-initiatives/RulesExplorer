# frozen_string_literal: true

require 'yaml'

class ScenariosFetchService
  def self.clone_git_repo
    raise if clone_url.blank?

    branch = 'master'
    if File.directory?(git_clone_folder)
      Rails.logger.info("Pull branch #{branch}")
      g = Git.init(git_clone_folder)
      g.checkout(branch)
      g.pull
    else
      Rails.logger.info("Cloning #{clone_url} into #{git_clone_folder}")
      g = Git.clone(clone_url, git_clone_folder)
      g.checkout(branch)
    end
  end

  def self.git_clone_folder
    "./tmp/#{ENV['RAILS_ENV']}-openfisca-aotearoa"
  end

  def self.clone_url
    ENV['OPENFISCA_GIT_CLONE_URL']
  end

  def self.yaml_tests_folder
    "#{git_clone_folder}/openfisca_aotearoa/tests/"
  end

  def self.fetch_all
    clone_git_repo
    found_scenarios = [] # Keep a running list of scenarios we found

    Find.find(yaml_tests_folder).each do |filename|
      next unless File.extname(filename) == '.yaml'

      Rails.logger.debug(filename)

      # https://github.com/ruby/psych/issues/262
      scenarios_list = YAML.load(File.read(filename)) # rubocop:disable Security/YAMLLoad
      scenario_names = scenarios_list.map { |s| s['name'] }
      found_scenarios += scenario_names
      Rails.logger.debug(scenario_names)
      find_all_duplicates(scenario_names)
      scenarios_list.each do |yaml_scenario|
        scenario = find_or_create_scenario(yaml_scenario)
      end
    end

    remove_stale_scenarios(scenario_names: found_scenarios)
  end

  def self.find_or_create_scenario(yaml_scenario)
    scenario_name = yaml_scenario['name']
    raise if scenario_name.blank?

    scenario = Scenario.find_or_initialize_by(name: scenario_name)

    ActiveRecord::Base.transaction do
      scenario.inputs = yaml_scenario['input']
      scenario.outputs = yaml_scenario['output']
      scenario.period = yaml_scenario['period']
      scenario.error_margin = yaml_scenario['absolute_error_margin']
      scenario.save!
      scenario.variables = fetch_associated_variables(yaml_scenario['input'], yaml_scenario['output'])
      scenario
    end
  end

  def self.fetch_associated_variables(inputs, outputs)
    input_keys = get_all_keys(inputs)
    output_keys = get_all_keys(outputs)
    input_output_keys = input_keys + output_keys
    # ensure they exist
    input_output_keys.each do |variable_name|
      Variable.find_or_create_by(name: variable_name)
    end
    Variable.where(name: input_output_keys)
  end

  # https://gist.github.com/naveed-ahmad/8f0b926ffccf5fbd206a1cc58ce9743e
  def self.find_all_duplicates(array)
    map = {}
    dup = []
    array.each do |v|
      map[v] = (map[v] || 0) + 1

      dup << v if map[v] == 2
    end
    raise StandardError.new("These scenarios have duplicate names: #{dup} !!!!!") if dup[0]
  end

  def self.remove_stale_scenarios(scenario_names:)
    Scenario
      .where
      .not(name: scenario_names)
      .destroy_all
  end

  # Needs to be updated to use github scraper
  def self.scrapped_data
    # Faraday.new ENV['OPENFISCA_URL'] do |conn|
    #   conn.response :json, content_type: /\bjson$/
    #   conn.adapter Faraday.default_adapter
    # end
  end

  # This could use some refinement
  # Currently it is returning all the keys
  # Can't just user lower level though because of data structures like:
  #  output:
  #   best_start__tax_credit_per_child:
  #     2018-07: [0, 0, 0, 260 ]

  def self.get_all_keys(hash)
    hash.each_with_object([]) do |(k, v), keys|
      keys << k
      keys.concat(get_all_keys(v)) if v.is_a? Hash
    end
  end
end
