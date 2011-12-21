require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require "rspec"

describe "Real Tests" do
  it "should do some real logging" do
    logger = Syslogger.new("real_logger")
    logger.error {"error test"}
    100.times do |i|
      logger.warn("warn test: #{i}")
    end

  end
end