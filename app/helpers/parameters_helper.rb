# frozen_string_literal: true

module ParametersHelper
  def filename_to_title(url)
    url.gsub('.yaml', '').split('/').last.titleize
  end

  def name_of_act(str)
    str.split('/').pop(2).first.titleize
  end

  def url_from_reference(ref)
    ref.match(%r{https?://[\S]+})
  end
end
