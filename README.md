### query_phantomjs_pagespeed.pl

Simple Perl script to scrape a page with PhantomJS and return pagespeed statistics to Cacti.

#### Usage

```
query_phantomjs_pagespeed.pl <webdriver url> <target url> [target number] [harlog path]
```

* webdriver url: URL of remote PhantomJS WebDriver server.
* target url: URL of page to be measured.
* target number: Optional, used to set cookie for load-balancer pool member selection.
* harlog path: If set, complete HTTP Archives (HAR logs) of every session will be stored to this path for later analysis.

#### Output

Script returns:
* resourceCount: Total number of resources required to load the page.
* firstResourceTime: Time until the first resource (ie; the page HTML itself) was completely loaded.
* localResourceTime: Time until all local resources (resources loadeded off the same domain as the page) were completely loaded.
* onloadTime: Time until the page's OnLoad event fired.

#### Notes

You must have one (or more) PhantomJS remote WebDrivers available. At the time I wrote this tool, PhantomJS session isolation didn't work properly, so the script protects access to the webdriver with a lock file.

