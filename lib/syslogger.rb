require 'syslog'
require 'logger'

class Syslogger

  VERSION = "1.2.6"

  attr_reader :level, :ident, :options, :facility

  MAPPING = {
    Logger::DEBUG => Syslog::LOG_DEBUG,
    Logger::INFO => Syslog::LOG_INFO,
    Logger::WARN => Syslog::LOG_NOTICE,
    Logger::ERROR => Syslog::LOG_WARNING,
    Logger::FATAL => Syslog::LOG_ERR,
    Logger::UNKNOWN => Syslog::LOG_ALERT
  }

  # Silences the logger for the duration of the block.
  def silence(temporary_level = ERROR)
    if true
      begin
        old_logger_level, self.level = level, temporary_level
        yield self
      ensure
        self.level = old_logger_level
      end
    else
      yield self
    end
  end

  #
  # Initializes default options for the logger
  # <tt>ident</tt>:: the name of your program [default=$0].
  # <tt>options</tt>::  syslog options [default=<tt>Syslog::LOG_PID | Syslog::LOG_CONS</tt>].
  #                     Correct values are:
  #                       LOG_CONS    : writes the message on the console if an error occurs when sending the message;
  #                       LOG_NDELAY  : no delay before sending the message;
  #                       LOG_PERROR  : messages will also be written on STDERR;
  #                       LOG_PID     : adds the process number to the message (just after the program name)
  # <tt>facility</tt>:: the syslog facility [default=nil] Correct values include:
  #                       Syslog::LOG_DAEMON
  #                       Syslog::LOG_USER
  #                       Syslog::LOG_SYSLOG
  #                       Syslog::LOG_LOCAL2
  #                       Syslog::LOG_NEWS
  #                       etc.
  #
  # Usage:
  #   logger = Syslogger.new("my_app", Syslog::LOG_PID | Syslog::LOG_CONS, Syslog::LOG_LOCAL0)
  #   logger.level = Logger::INFO # use Logger levels
  #   logger.warn "warning message"
  #   logger.debug "debug message"
  #
  def initialize(ident = $0, options = Syslog::LOG_PID | Syslog::LOG_CONS, facility = nil)
    @ident = ident
    @options = options || (Syslog::LOG_PID | Syslog::LOG_CONS)
    @facility = facility
    @level = Logger::DEBUG
    # give up a little flexibilty for some performance gains
    @sys_log = Syslog.open(@ident, @options, @facility)
    @sys_log_lock = Mutex.new
  end

  #%w{debug info warn error fatal unknown}.each do |logger_method|
  #  define_method logger_method.to_sym do |message|
  #    add(Logger.const_get(logger_method.upcase), message)
  #  end
  #
  #  unless logger_method == 'unknown'
  #    define_method "#{logger_method}?".to_sym do
  #      @level <= Logger.const_get(logger_method.upcase)
  #    end
  #  end
  #end

  # Dynamically add methods such as:
  # def info
  # def warn
  # def debug
  %w{debug info warn error fatal unknown}.each do |severity|
    log_level = Logger.const_get(severity.upcase)
    class_eval <<-EOT, __FILE__, __LINE__ + 1
      def #{severity.downcase}(message = nil, progname = nil, &block) # def debug(message = nil, progname = nil, &block)
        add(#{log_level}, message, progname, &block)                   #   add(DEBUG, message, progname, &block)
      end                                                             # end

      def #{severity.downcase}?                                       # def debug?
        #{log_level} >= @level                                         #   DEBUG >= @level
      end                                                             # end
    EOT
  end

  # Logs a message at the Logger::INFO level.
  def <<(msg)
    add(Logger::INFO, msg)
  end

  # Low level method to add a message.
  # +severity+::  the level of the message. One of Logger::DEBUG, Logger::INFO, Logger::WARN, Logger::ERROR, Logger::FATAL, Logger::UNKNOWN
  # +message+:: the message string. 
  #             If nil, the method will call the block and use the result as the message string. 
  #             If both are nil or no block is given, it will use the progname as per the behaviour of both the standard Ruby logger, and the Rails BufferedLogger.
  # +progname+:: optionally, overwrite the program name that appears in the log message.
  def add(severity, message = nil, progname = nil, &block)
    return if @level > severity
    progname ||= @ident
    msg = clean(message || (block && block.call) || progname)
    s = @sys_log
    @sys_log_lock.synchronize do
      s.mask = Syslog::LOG_UPTO(MAPPING[@level])
      s.log(
        MAPPING[severity],
        msg
      )
    end
  end

  # Sets the minimum level for messages to be written in the log.
  # +level+:: one of <tt>Logger::DEBUG</tt>, <tt>Logger::INFO</tt>, <tt>Logger::WARN</tt>, <tt>Logger::ERROR</tt>, <tt>Logger::FATAL</tt>, <tt>Logger::UNKNOWN</tt>
  def level=(level)
    @level = level
  end

  protected

  # Borrowed from SyslogLogger.
  def clean(message)
    message = message.to_s.dup
    message.rstrip!
    message.gsub!(/%/, '%%') # syslog(3) freaks on % (printf)
    message
  end
end
