#!/usr/bin/perl

use strict;
use WWW::Curl::Easy;
use Data::Dumper;
use Date::Parse;
use Time::HiRes 'sleep';
use URI::Escape;
use JSON;

my $WEBDRIVER_URL = shift(@ARGV) || 'http://localhost:8080';
my $TARGET_URL = shift(@ARGV) || 'https://www.cnn.com';
my $TARGET_NUM = shift(@ARGV) || 1;
my $HARLOG_PATH = shift(@ARGV)
my $TMPDIR = $ENV['TMPDIR'] || '/var/tmp';

my $MAX_LOCK_TIME = 15;
my $CURL_TIMEOUT = 5;
my $CURL_TIMEOUT_SETURL = 15;
my $CURL = WWW::Curl::Easy->new();
   $CURL->setopt(CURLOPT_PROXY, '');

$| = 1;

lockWebdriver();
my $session = getSession();
if ($session){
  if (execPhantomScript($session, 'this.clearCookies(); this.clearMemoryCache(); return true;')){
    if (setCookie($session, $TARGET_NUM)){
      if (setWindowSize($session, 1024, 768)){
        if (setUrl($session, $TARGET_URL)){
          if (my $harData = getHAR($session)){
            if ($HARLOG_PATH){
              my $url = uri_escape($TARGET_URL);
              my ($date, $time) = $harData->{'log'}{'pages'}[0]{'startedDateTime'} =~ m/(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})/;
              mkdir("$HARLOG_PATH/$date", 0775);
              if(open(my $FH, ">$HARLOG_PATH/$date/$url-$TARGET_NUM-$time.har")){
                print $FH encode_json($harData);
                close($FH);
              }
            }
            my ($pageDomain) = $harData->{'log'}{'entries'}[0]{'request'}{'url'} =~ m|://(.*?)/|;
            my $entryCount = scalar(@{$harData->{'log'}{'entries'}});
            my $firstTime = $harData->{'log'}{'entries'}[0]{'time'};
            my $onloadTime = $harData->{'log'}{'pages'}[0]{'pageTimings'}{'onLoad'};
            my $localTime = 0;
            my $localStart = 2147483647;
            my $localEnd = 0;
            my @entries = @{$harData->{'log'}{'entries'}};
            shift(@entries);
            foreach my $entry (@entries){
              my ($resourceDomain) = $entry->{'request'}{'url'} =~ m|://(.*?)/|; 
              if ($resourceDomain eq $pageDomain){
                my $startTime = str2time($entry->{'startedDateTime'});
                my $endTime = $startTime + ($entry->{'time'}/ 1000);
                if ($startTime < $localStart) { $localStart = $startTime };
                if ($endTime > $localEnd) { $localEnd = $endTime };
              }
            }
            if ($localEnd){
              $localTime = ($localEnd - $localStart) * 1000;
            }
            printf("resourceCount:%d firstResourceTime:%d localResourceTime:%d onloadTime:%d",
                   $entryCount,
                   $firstTime,
                   $localTime,
                   $onloadTime);
            print STDERR "\n";
          }
        }
      }
    }
  }
  deleteSession($session);
}
unlockWebdriver();

sub lockWebdriver {
  my $lock = $TMPDIR.'/.webdriver-'.uri_escape($WEBDRIVER_URL).'.lock';
  my $FH;
  my $is_locked = 0;
  my $sleep_time = 0;
  do {
    $is_locked = 0;
    if (-f $lock){
      open($FH, "<$lock");
      if ($FH){ # file could have been removed between the test and the open
        my $pid = readline($FH);
        close($FH);
        chomp $pid;
        if (-e "/proc/$pid"){
          #print STDERR "Lock file $lock exists and PID $pid is still alive - waiting for webdriver to become free\n";
          $is_locked = 1;
          $sleep_time += sleep(0.5);
        }
      }
    }
  } while ($is_locked && $sleep_time < $MAX_LOCK_TIME);

  if ($is_locked){
    die "Failed to acquire WebDriver lock after $sleep_time seconds\n"
  }

  open ($FH, ">$lock") or die "Failed to open lock file: $!";
  print $FH "$$\n";
  close($FH);
}

sub unlockWebdriver {
  my $lock = $TMPDIR.'/.webdriver-'.uri_escape($WEBDRIVER_URL).'.lock';
  unlink $lock; 
}

sub getSession {
  my $capsParam = {'desiredCapabilities' => {
                'version'     => '1.2',
                'platform'    => 'WINDOWS',
                'browserName' => 'phantomjs',
                'phantomjs.page.settings.userAgent' => 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:37.0) Gecko/20100101 Firefox/37.0',
                'phantomjs.page.customHeaders.X-PhantomJS-SessionTS' => time(),
                'phantomjs.page.customHeaders.X-Monitoring-Request' => 'True' }
              };
  my $ret = doCurlPost("$WEBDRIVER_URL/session", $capsParam);
  if ($ret->{'status'} != 0){
    warn "Failed to create session: ".$ret->{'error'};
  }
  return $ret->{'sessionId'};
}

sub setCookie {
  my $sessionId = shift || return;
  my $value = shift || $TARGET_NUM;
  my $name = shift || 'F5PoolMemberSelector';
  my $domain = shift || (map {m|://.*?(\w+\.\w+)/|; ".$1"} $TARGET_URL)[0];
  my $path = shift || '/';
  my $cookieParam = {'cookie' => {'name' => $name, 'path' => $path, 'domain' => $domain, 'value' => $value}};
  my $ret = doCurlPost("$WEBDRIVER_URL/session/$sessionId/cookie", $cookieParam);
  if ($ret->{'status'} != 0){
    warn "Failed to set cookie for session $sessionId: ".$ret->{'error'};
  }
  return $ret->{'value'};
}

sub setWindowSize {
  my $sessionId = shift || return;
  my $width = shift || 1024;
  my $height = shift || 768;
  my $sizeParam = {'width' => $width, 'height' => $height};
  my $ret = doCurlPost("$WEBDRIVER_URL/session/$sessionId/window/current/size", $sizeParam);
  if ($ret->{'status'} != 0){
    warn "Failed to set window size: ".$ret->{'error'};
  }
  return $ret->{'value'};
}

sub setUrl {
  my $sessionId = shift || return;
  my $url = shift || return;
  my $urlParam = {'url' => $url};
  my $ret = doCurlPost("$WEBDRIVER_URL/session/$sessionId/url", $urlParam, $CURL_TIMEOUT_SETURL);
  if ($ret->{'status'} != 0){
    warn "Failed to set URL: ".$ret->{'error'};
  }
  return $ret->{'value'}; 
}

sub execPhantomScript {
  my $sessionId = shift || return;
  my $script = shift || return;
  my $args = \@_ || [];
  my $execParam = {'script' => $script, 'args' => $args};
  my $ret = doCurlPost("$WEBDRIVER_URL/session/$sessionId/phantom/execute", $execParam);
  if ($ret->{'status'} != 0){
    warn "Failed to execute PhansomJS script: ".$ret->{'error'};
  }
  return $ret->{'value'};
}

sub getHAR {
  my $sessionId = shift || return;
  my $typeParam = {'type' => 'har'};
  my $ret = doCurlPost("$WEBDRIVER_URL/session/$sessionId/log", $typeParam);
  if ($ret->{'status'} != 0){
    warn "Failed to get HAR for session $sessionId: ".$ret->{'error'};
    return $ret->{'value'}
  } else {
    my $harData = decode_json($ret->{'value'}[0]{'message'});
    # The PhantomDriver HAR creation process fails to properly exclude all data URIs
    $harData->{'log'}{'entries'} = [grep { $_->{'request'}{'url'} !~ m/^data:/ } @{$harData->{'log'}{'entries'}}];
    return $harData;
  }
}

sub deleteSession {
  my $sessionId = shift || return;
  my $ret = doCurlDelete("$WEBDRIVER_URL/session/$sessionId");
  if ($ret->{'status'} != 0){
    warn "Failed to execute PhansomJS script for session $sessionId: ".$ret->{'error'};
  }
  return $ret->{'value'};
}

sub doCurlDelete {
  my $url = shift || return;
  my $time = shift || $CURL_TIMEOUT;
  my $file;
  my $data;
  open($file, '>', \$data);
  $CURL->setopt(CURLOPT_URL, $url);
  $CURL->setopt(CURLOPT_TIMEOUT, $time);
  $CURL->setopt(CURLOPT_WRITEDATA, $file);
  $CURL->setopt(CURLOPT_POST, 0);
  $CURL->setopt(CURLOPT_CUSTOMREQUEST, 'DELETE');
  my $ret = $CURL->perform();
  my $code = $CURL->getinfo(CURLINFO_HTTP_CODE);
  close($file);
  if ($ret == 0 && $code == 200){
    eval { $data = decode_json($data) };
    if (!$@){
      return $data;
    } else {
      return {'status' => -1, 'error' => 'Failed to parse JSON response'};
    }
  } else {
    if ($ret != 0){
      return {'status' => $ret, 'error' => $CURL->strerror($ret)};
    } else {
      $data =~ s/ - .+//;
      return {'status' => $code, 'error' => $data};
    }
  }
}

sub doCurlPost {
  my $url = shift || return;
  my $json = encode_json(shift);
  my $time = shift || $CURL_TIMEOUT;
  my $CURL = WWW::Curl::Easy->new();
  my $file;
  my $data;
  open($file, '>', \$data);
  $CURL->setopt(CURLOPT_URL, $url);
  $CURL->setopt(CURLOPT_TIMEOUT, $time);
  $CURL->setopt(CURLOPT_WRITEDATA, $file);
  $CURL->setopt(CURLOPT_CUSTOMREQUEST, undef);
  $CURL->setopt(CURLOPT_POST, 1);
  $CURL->setopt(CURLOPT_POSTFIELDS, $json);
  my $ret = $CURL->perform();
  my $code = $CURL->getinfo(CURLINFO_HTTP_CODE);
  close($file);
  if ($ret == 0 && $code == 200){
    eval { $data = decode_json($data) };
    if (!$@){
      return $data;
    } else {
      return {};
    }
  } else {
    if ($ret != 0){
      return {'status' => $ret, 'error' => $CURL->strerror($ret)};
    } else {
      $data =~ s/ - .+//;
      return {'status' => $code, 'error' => $data};
    }
  }
}
