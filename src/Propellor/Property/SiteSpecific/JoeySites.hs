-- | Specific configuation for Joey Hess's sites. Probably not useful to
-- others except as an example.

module Propellor.Property.SiteSpecific.JoeySites where

import Propellor
import qualified Propellor.Property.Apt as Apt
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Gpg as Gpg
import qualified Propellor.Property.Ssh as Ssh
import qualified Propellor.Property.Git as Git
import qualified Propellor.Property.Cron as Cron
import qualified Propellor.Property.Service as Service
import qualified Propellor.Property.User as User
import qualified Propellor.Property.Obnam as Obnam
import qualified Propellor.Property.Apache as Apache
import qualified Propellor.Property.Postfix as Postfix
import Utility.SafeCommand
import Utility.FileMode
import Utility.Path

import Data.List
import System.Posix.Files

oldUseNetServer :: [Host] -> Property
oldUseNetServer hosts = propertyList ("olduse.net server")
	[ oldUseNetInstalled "oldusenet-server"
	, Obnam.latestVersion
	, Obnam.backup datadir "33 4 * * *"
		[ "--repository=sftp://2318@usw-s002.rsync.net/~/olduse.net"
		, "--client-name=spool"
		] Obnam.OnlyClient
		`requires` Ssh.keyImported SshRsa "root" (Context "olduse.net")
		`requires` Ssh.knownHost hosts "usw-s002.rsync.net" "root"
	, check (not . isSymbolicLink <$> getSymbolicLinkStatus newsspool) $
		property "olduse.net spool in place" $ makeChange $ do
			removeDirectoryRecursive newsspool
			createSymbolicLink (datadir </> "news") newsspool
	, Apt.installed ["leafnode"]
	, "/etc/news/leafnode/config" `File.hasContent` 
		[ "# olduse.net configuration (deployed by propellor)"
		, "expire = 1000000" -- no expiry via texpire
		, "server = " -- no upstream server
		, "debugmode = 1"
		, "allowSTRANGERS = 42" -- lets anyone connect
		, "nopost = 1" -- no new posting (just gather them)
		]
	, "/etc/hosts.deny" `File.lacksLine` "leafnode: ALL"
	, Apt.serviceInstalledRunning "openbsd-inetd"
	, File.notPresent "/etc/cron.daily/leafnode"
	, File.notPresent "/etc/cron.d/leafnode"
	, Cron.niceJob "oldusenet-expire" "11 1 * * *" "news" newsspool $ intercalate ";"
		[ "find \\( -path ./out.going -or -path ./interesting.groups -or -path './*/.overview' \\) -prune -or -type f -ctime +60  -print | xargs --no-run-if-empty rm"
		, "find -type d -empty | xargs --no-run-if-empty rmdir"
		]
	, Cron.niceJob "oldusenet-uucp" "*/5 * * * *" "news" "/" $
		"/usr/bin/uucp " ++ datadir
	, toProp $ Apache.siteEnabled "nntp.olduse.net" $ apachecfg "nntp.olduse.net" False
		[ "  DocumentRoot " ++ datadir ++ "/"
		, "  <Directory " ++ datadir ++ "/>"
		, "    Options Indexes FollowSymlinks"
		, "    AllowOverride None"
		-- I had this in the file before.
		-- This may be needed by a newer version of apache?
		--, "    Require all granted"
		, "  </Directory>"
		]
	]
  where
	newsspool = "/var/spool/news"
	datadir = "/var/spool/oldusenet"

oldUseNetShellBox :: Property
oldUseNetShellBox = oldUseNetInstalled "oldusenet"

oldUseNetInstalled :: Apt.Package -> Property
oldUseNetInstalled pkg = check (not <$> Apt.isInstalled pkg) $
	propertyList ("olduse.net " ++ pkg)
		[ Apt.installed (words "build-essential devscripts debhelper git libncursesw5-dev libpcre3-dev pkg-config bison libicu-dev libidn11-dev libcanlock2-dev libuu-dev ghc libghc-strptime-dev libghc-hamlet-dev libghc-ifelse-dev libghc-hxt-dev libghc-utf8-string-dev libghc-missingh-dev libghc-sha-dev")
			`describe` "olduse.net build deps"
		, scriptProperty
			[ "rm -rf /root/tmp/oldusenet" -- idenpotency
			, "git clone git://olduse.net/ /root/tmp/oldusenet/source"
			, "cd /root/tmp/oldusenet/source/"
			, "dpkg-buildpackage -us -uc"
			, "dpkg -i ../" ++ pkg ++ "_*.deb || true"
			, "apt-get -fy install" -- dependencies
			, "rm -rf /root/tmp/oldusenet"
			-- screen fails unless the directory has this mode.
			-- not sure what's going on.
			, "chmod 777 /var/run/screen"
			] `describe` "olduse.net built"
		]


kgbServer :: Property
kgbServer = propertyList desc
	[ withOS desc $ \o -> case o of
		(Just (System (Debian Unstable) _)) ->
			ensureProperty $ propertyList desc
				[ Apt.serviceInstalledRunning "kgb-bot"
				, "/etc/default/kgb-bot" `File.containsLine` "BOT_ENABLED=1"
					`describe` "kgb bot enabled"
					`onChange` Service.running "kgb-bot"
				]
		_ -> error "kgb server needs Debian unstable (for kgb-bot 1.31+)"
	, File.hasPrivContent "/etc/kgb-bot/kgb.conf" anyContext
		`onChange` Service.restarted "kgb-bot"
	]
  where
	desc = "kgb.kitenet.net setup"

mumbleServer :: [Host] -> Property
mumbleServer hosts = combineProperties hn
	[ Apt.serviceInstalledRunning "mumble-server"
	, Obnam.latestVersion
	, Obnam.backup "/var/lib/mumble-server" "55 5 * * *"
		[ "--repository=sftp://joey@turtle.kitenet.net/~/lib/backup/" ++ hn ++ ".obnam"
		, "--client-name=mumble"
		] Obnam.OnlyClient
		`requires` Ssh.keyImported SshRsa "root" (Context hn)
		`requires` Ssh.knownHost hosts "turtle.kitenet.net" "root"
	, trivial $ cmdProperty "chown" ["-R", "mumble-server:mumble-server", "/var/lib/mumble-server"]
	]
  where
	hn = "mumble.debian.net"

obnamLowMem :: Property
obnamLowMem = combineProperties "obnam tuned for low memory use"
	[ Obnam.latestVersion
	, "/etc/obnam.conf" `File.containsLines`
		[ "[config]"
		, "# Suggested by liw to keep Obnam memory consumption down (at some speed cost)."
		, "upload-queue-size = 128"
		, "lru-size = 128"
		]
	]

-- git.kitenet.net and git.joeyh.name
gitServer :: [Host] -> Property
gitServer hosts = propertyList "git.kitenet.net setup"
	[ Obnam.latestVersion
	, Obnam.backup "/srv/git" "33 3 * * *"
		[ "--repository=sftp://2318@usw-s002.rsync.net/~/git.kitenet.net"
		, "--encrypt-with=1B169BE1"
		, "--client-name=wren" -- historical
		] Obnam.OnlyClient
		`requires` Gpg.keyImported "1B169BE1" "root"
		`requires` Ssh.keyImported SshRsa "root" (Context "git.kitenet.net")
		`requires` Ssh.knownHost hosts "usw-s002.rsync.net" "root"
		`requires` Ssh.authorizedKeys "family" (Context "git.kitenet.net")
		`requires` User.accountFor "family"
	, Apt.installed ["git", "rsync", "gitweb"]
	-- backport avoids channel flooding on branch merge
	, Apt.installedBackport ["kgb-client"]
	-- backport supports ssh event notification
	, Apt.installedBackport ["git-annex"]
	, File.hasPrivContentExposed "/etc/kgb-bot/kgb-client.conf" anyContext
	, toProp $ Git.daemonRunning "/srv/git"
	, "/etc/gitweb.conf" `File.containsLines`
		[ "$projectroot = '/srv/git';"
		, "@git_base_url_list = ('git://git.kitenet.net', 'http://git.kitenet.net/git', 'https://git.kitenet.net/git', 'ssh://git.kitenet.net/srv/git');"
		, "# disable snapshot download; overloads server"
		, "$feature{'snapshot'}{'default'} = [];"
		]
		`describe` "gitweb configured"
	-- Repos push on to github.
	, Ssh.knownHost hosts "github.com" "joey"
	-- I keep the website used for gitweb checked into git..
	, Git.cloned "root" "/srv/git/joey/git.kitenet.net.git" "/srv/web/git.kitenet.net" Nothing
	, website "git.kitenet.net"
	, website "git.joeyh.name"
	, toProp $ Apache.modEnabled "cgi"
	]
  where
	website hn = toProp $ Apache.siteEnabled hn $ apachecfg hn True
		[ "  DocumentRoot /srv/web/git.kitenet.net/"
		, "  <Directory /srv/web/git.kitenet.net/>"
		, "    Options Indexes ExecCGI FollowSymlinks"
		, "    AllowOverride None"
		, "    AddHandler cgi-script .cgi"
		, "    DirectoryIndex index.cgi"
		, "  </Directory>"
		, ""
		, "  ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/"
		, "  <Directory /usr/lib/cgi-bin>"
		, "    SetHandler cgi-script"
		, "    Options ExecCGI"
		, "  </Directory>"
		]

type AnnexUUID = String

-- | A website, with files coming from a git-annex repository.
annexWebSite :: Git.RepoUrl -> HostName -> AnnexUUID -> [(String, Git.RepoUrl)] -> Property
annexWebSite origin hn uuid remotes = propertyList (hn ++" website using git-annex")
	[ Git.cloned "joey" origin dir Nothing
		`onChange` setup
	, postupdatehook `File.hasContent`
		[ "#!/bin/sh"
		, "exec git update-server-info"
		] `onChange`
			(postupdatehook `File.mode` (combineModes (ownerWriteMode:readModes ++ executeModes)))
	, setupapache
	]
  where
	dir = "/srv/web/" ++ hn
	postupdatehook = dir </> ".git/hooks/post-update"
	setup = userScriptProperty "joey" setupscript
	setupscript = 
		[ "cd " ++ shellEscape dir
		, "git config annex.uuid " ++ shellEscape uuid
		] ++ map addremote remotes ++
		[ "git annex get"
		]
	addremote (name, url) = "git remote add " ++ shellEscape name ++ " " ++ shellEscape url
	setupapache = toProp $ Apache.siteEnabled hn $ apachecfg hn True $ 
		[ "  ServerAlias www."++hn
		, ""
		, "  DocumentRoot /srv/web/"++hn
		, "  <Directory /srv/web/"++hn++">"
		, "    Options FollowSymLinks"
		, "    AllowOverride None"
		, "  </Directory>"
		, "  <Directory /srv/web/"++hn++">"
		, "    Options Indexes FollowSymLinks ExecCGI"
		, "    AllowOverride None"
		, "    AddHandler cgi-script .cgi"
		, "    DirectoryIndex index.html index.cgi"
		, "    Order allow,deny"
		, "    allow from all"
		, "  </Directory>"
		]

apachecfg :: HostName -> Bool -> Apache.ConfigFile -> Apache.ConfigFile
apachecfg hn withssl middle
	| withssl = vhost False ++ vhost True
	| otherwise = vhost False
  where
	vhost ssl = 
		[ "<VirtualHost *:"++show port++">"
		, "  ServerAdmin grue@joeyh.name"
		, "  ServerName "++hn++":"++show port
		]
		++ mainhttpscert ssl
		++ middle ++
		[ ""
		, "  ErrorLog /var/log/apache2/error.log"
		, "  LogLevel warn"
		, "  CustomLog /var/log/apache2/access.log combined"
		, "  ServerSignature On"
		, "  "
		, "  <Directory \"/usr/share/apache2/icons\">"
		, "      Options Indexes MultiViews"
		, "      AllowOverride None"
		, "      Order allow,deny"
		, "      Allow from all"
		, "  </Directory>"
		, "</VirtualHost>"
		]
	  where
		port = if ssl then 443 else 80 :: Int

mainhttpscert :: Bool -> Apache.ConfigFile
mainhttpscert False = []
mainhttpscert True = 
	[ "  SSLEngine on"
	, "  SSLCertificateFile /etc/ssl/certs/web.pem"
	, "  SSLCertificateKeyFile /etc/ssl/private/web.pem"
	, "  SSLCertificateChainFile /etc/ssl/certs/startssl.pem"
	]
		
gitAnnexDistributor :: Property
gitAnnexDistributor = combineProperties "git-annex distributor, including rsync server and signer"
	[ Apt.installed ["rsync"]
	, File.hasPrivContent "/etc/rsyncd.conf" (Context "git-annex distributor")
		`onChange` Service.restarted "rsync"
	, File.hasPrivContent "/etc/rsyncd.secrets" (Context "git-annex distributor")
		`onChange` Service.restarted "rsync"
	, "/etc/default/rsync" `File.containsLine` "RSYNC_ENABLE=true"
		`onChange` Service.running "rsync"
	, endpoint "/srv/web/downloads.kitenet.net/git-annex/autobuild"
	, endpoint "/srv/web/downloads.kitenet.net/git-annex/autobuild/x86_64-apple-mavericks"
	-- git-annex distribution signing key
	, Gpg.keyImported "89C809CB" "joey"
	]
  where
	endpoint d = combineProperties ("endpoint " ++ d)
		[ File.dirExists d
		, File.ownerGroup d "joey" "joey"
		]

-- Twitter, you kill us.
twitRss :: Property
twitRss = combineProperties "twitter rss"
	[ Git.cloned "joey" "git://git.kitenet.net/twitrss.git" dir Nothing
	, check (not <$> doesFileExist (dir </> "twitRss")) $
		userScriptProperty "joey"
			[ "cd " ++ dir
			, "ghc --make twitRss" 
			]
			`requires` Apt.installed
				[ "libghc-xml-dev"
				, "libghc-feed-dev"
				, "libghc-tagsoup-dev"
				]
	, feed "http://twitter.com/search/realtime?q=git-annex" "git-annex-twitter"
	, feed "http://twitter.com/search/realtime?q=olduse+OR+git-annex+OR+debhelper+OR+etckeeper+OR+ikiwiki+-ashley_ikiwiki" "twittergrep"
	]
  where
	dir = "/srv/web/tmp.kitenet.net/twitrss"
	crontime = "15 * * * *"
	feed url desc = Cron.job desc crontime "joey" dir $
		"./twitRss " ++ shellEscape url ++ " > " ++ shellEscape ("../" ++ desc ++ ".rss")

ircBouncer :: Property
ircBouncer = propertyList "IRC bouncer"
	[ Apt.installed ["znc"]
	, User.accountFor "znc"
	, File.dirExists (parentDir conf)
	, File.hasPrivContent conf anyContext
	, File.ownerGroup conf "znc" "znc"
	, Cron.job "znconboot" "@reboot" "znc" "~" "znc"
	-- ensure running if it was not already
	, trivial $ userScriptProperty "znc" ["znc || true"]
		`describe` "znc running"
	]
  where
	conf = "/home/znc/.znc/configs/znc.conf"

kiteShellBox :: Property
kiteShellBox = propertyList "kitenet.net shellinabox"
	[ Apt.installed ["shellinabox"]
	, File.hasContent "/etc/default/shellinabox"
		[ "# Deployed by propellor"
		, "SHELLINABOX_DAEMON_START=1"
		, "SHELLINABOX_PORT=443"
		, "SHELLINABOX_ARGS=\"--no-beep --service=/:SSH:kitenet.net\""
		]
		`onChange` Service.restarted "shellinabox"
	, Service.running "shellinabox"
	]

githubBackup :: Property
githubBackup = propertyList "github-backup box"
	[ Apt.installed ["github-backup", "moreutils"]
	, let f = "/home/joey/.github-keys"
	  in File.hasPrivContent f anyContext
		`onChange` File.ownerGroup f "joey" "joey"
	, Cron.niceJob "github-backup run" "30 4 * * *" "joey"
		"/home/joey/lib/backup" $ intercalate "&"
			[ "mkdir -p github"
			, "cd github"
			, ". $HOME/.github-keys && github-backup joeyh"
			]
	]

rsyncNetBackup :: [Host] -> Property
rsyncNetBackup hosts = Cron.niceJob "rsync.net copied in daily" "30 5 * * *"
	"joey" "/home/joey/lib/backup" "mkdir -p rsync.net && rsync --delete -az 2318@usw-s002.rsync.net: rsync.net"
	`requires` Ssh.knownHost hosts "usw-s002.rsync.net" "joey"

backupsBackedupTo :: [Host] -> HostName -> FilePath -> Property
backupsBackedupTo hosts desthost destdir = Cron.niceJob desc
	"1 1 * * 3" "joey" "/" cmd
	`requires` Ssh.knownHost hosts desthost "joey"
  where
	desc = "backups copied to " ++ desthost ++ " weekly"
	cmd = "rsync -az --delete /home/joey/lib/backup " ++ desthost ++ ":" ++ destdir

obnamRepos :: [String] -> Property
obnamRepos rs = propertyList ("obnam repos for " ++ unwords rs)
	(mkbase : map mkrepo rs)
  where
  	mkbase = mkdir "/home/joey/lib/backup"
		`requires` mkdir "/home/joey/lib"
	mkrepo r = mkdir ("/home/joey/lib/backup/" ++ r ++ ".obnam")
	mkdir d = File.dirExists d
		`before` File.ownerGroup d "joey" "joey"

podcatcher :: Property
podcatcher = Cron.niceJob "podcatcher run hourly" "55 * * * *"
	"joey" "/home/joey/lib/sound/podcasts"
	"xargs git-annex importfeed -c annex.genmetadata=true < feeds; mr --quiet update"
	`requires` Apt.installed ["git-annex", "myrepos"]

kiteMailServer :: Property
kiteMailServer = propertyList "kitenet.net mail server"
	[ Postfix.installed
	, Apt.installed ["postfix-pcre"]
	, Apt.serviceInstalledRunning "postgrey"

	, Apt.serviceInstalledRunning "spamassassin"
	, "/etc/default/spamassassin" `File.containsLines`
		[ "# Propellor deployed"
		, "ENABLED=1"
		, "CRON=1"
		, "OPTIONS=\"--create-prefs --max-children 5 --helper-home-dir\""
		, "CRON=1"
		, "NICE=\"--nicelevel 15\""
		] `onChange` Service.restarted "spamassassin"
		`describe` "spamd enabled"
		`requires` Apt.serviceInstalledRunning "cron"
	
	, Apt.serviceInstalledRunning "spamass-milter"
	-- Add -m to prevent modifying messages Subject or body.
	, "/etc/default/spamass-milter" `File.containsLine`
		"OPTIONS=\"-m -u spamass-milter -i 127.0.0.1\""
		`onChange` Service.restarted "spamass-milter"
		`describe` "spamass-milter configured"
	
	, Apt.serviceInstalledRunning "amavisd-milter"
	, "/etc/default/amavisd-milter" `File.containsLines`
		[ "# Propellor deployed"
		, "MILTERSOCKET=/var/spool/postfix/amavis/amavis.sock"
		, "MILTERSOCKETOWNER=\"postfix:postfix\""
		, "MILTERSOCKETMODE=\"0660\""
		]
		`onChange` Service.restarted "amavisd-milter"
		`describe` "amavisd-milter configured for postfix"
	, Apt.serviceInstalledRunning "clamav-freshclam"

	, Apt.installed ["maildrop"]
	, "/etc/maildroprc" `File.hasContent`
		[ "# Global maildrop filter file (deployed with propellor)"
		, "DEFAULT=\"$HOME/Maildir\""
		, "MAILBOX=\"$DEFAULT/.\""
		, "# Filter spam to a spam folder, unless .keepspam exists"
		, "if (/^X-Spam-Status: Yes/)"
		, "{"
		, "  `test -e \"$HOME/.keepspam\"`"
		, "  if ( $RETURNCODE != 0 )"
		, "  to ${MAILBOX}spam"
		, "}"
		]
		`describe` "maildrop configured"

	, "/etc/aliases" `File.hasPrivContentExposed` ctx
		`onChange` Postfix.newaliases
	, hasJoeyCAChain
	, "/etc/ssl/certs/postfix.pem" `File.hasPrivContentExposed` ctx
	, "/etc/ssl/private/postfix.pem" `File.hasPrivContent` ctx

	, "/etc/postfix/mydomain" `File.containsLines`
		[ "/.*\\.kitenet\\.net/\tOK"
		, "/ikiwiki\\.info/\tOK"
		, "/joeyh\\.name/\tOK"
		]
		`onChange` Postfix.reloaded
		`describe` "postfix mydomain file configured"
	, "/etc/postfix/obscure_client_relay.pcre" `File.containsLine`
		"/^Received: from ([^.]+)\\.kitenet\\.net.*using TLS.*by kitenet\\.net \\(([^)]+)\\) with (E?SMTPS?A?) id ([A-F[:digit:]]+)(.*)/ IGNORE"
		`onChange` Postfix.reloaded
		`describe` "postfix obscure_client_relay file configured"
	, Postfix.mappedFile "/etc/postfix/virtual"
		(flip File.containsLines
			[ "# *@joeyh.name to joey"
			, "@joeyh.name\tjoey"
			]
		) `describe` "postfix virtual file configured"
		`onChange` Postfix.reloaded
	, Postfix.mappedFile "/etc/postfix/relay_clientcerts" $
		flip File.hasPrivContentExposed ctx
	, Postfix.mainCfFile `File.containsLines`
		[ "myhostname = kitenet.net"
		, "mydomain = $myhostname"
		, "append_dot_mydomain = no"
		, "myorigin = kitenet.net"
		, "mydestination = $myhostname, localhost.$mydomain, $mydomain, kite.$mydomain., localhost, regexp:$config_directory/mydomain"
		, "mailbox_command = maildrop"
		, "virtual_alias_maps = hash:/etc/postfix/virtual"

		, "# Allow clients with trusted certs to relay mail through."
		, "relay_clientcerts = hash:/etc/postfix/relay_clientcerts"
		, "smtpd_relay_restrictions = permit_mynetworks,permit_tls_clientcerts,permit_sasl_authenticated,reject_unauth_destination"

		, "# Filter out client relay lines from headers."
		, "header_checks = pcre:$config_directory/obscure_client_relay.pcre"

		, "# Enable postgrey."
		, "smtpd_recipient_restrictions = permit_mynetworks,reject_unauth_destination,check_policy_service inet:127.0.0.1:10023"

		, "# Enable spamass-milter and amavis-milter."
		, "smtpd_milters = unix:/spamass/spamass.sock unix:amavis/amavis.sock"
		, "milter_connect_macros = j {daemon_name} v {if_name} _"

		, "# TLS setup -- server"
		, "smtpd_tls_CAfile = /etc/ssl/certs/joeyca.pem"
		, "smtpd_tls_cert_file = /etc/ssl/certs/postfix.pem"
		, "smtpd_tls_key_file = /etc/ssl/private/postfix.pem"
		, "smtpd_tls_loglevel = 1"
		, "smtpd_tls_received_header = yes"
		, "smtpd_use_tls = yes"
		, "smtpd_tls_ask_ccert = yes"
		, "smtpd_tls_session_cache_database = sdbm:/etc/postfix/smtpd_scache"

		, "# TLS setup -- client"
		, "smtp_tls_CAfile = /etc/ssl/certs/joeyca.pem"
		, "smtp_tls_cert_file = /etc/ssl/certs/postfix.pem"
		, "smtp_tls_key_file = /etc/ssl/private/postfix.pem"
		, "smtp_tls_loglevel = 1"
		, "smtp_use_tls = yes"
		, "smtp_tls_session_cache_database = sdbm:/etc/postfix/smtp_scache"
		]
		`onChange` Postfix.dedupMainCf
		`onChange` Postfix.reloaded
		`describe` "postfix configured"
	
	, Apt.serviceInstalledRunning "dovecot-imapd"
	, Apt.serviceInstalledRunning "dovecot-pop3d"
	, "/etc/dovecot/conf.d/10-mail.conf" `File.containsLine`
		"mail_location = maildir:~/Maildir"
		`onChange` Service.reloaded "dovecot"
		`describe` "dovecot mail.conf"
	, "/etc/dovecot/conf.d/10-auth.conf" `File.containsLine`
		"!include auth-passwdfile.conf.ext"
		`onChange` Service.restarted "dovecot"
		`describe` "dovecot auth.conf"
	, File.hasPrivContent dovecotusers ctx
		`onChange` (dovecotusers `File.mode`
			combineModes [ownerReadMode, groupReadMode])
	, File.ownerGroup dovecotusers "root" "dovecot"

	, Apt.installed ["mutt", "bsd-mailx", "alpine"]

	, pinescript `File.hasContent`
		[ "#!/bin/sh"
		, "# deployed with propellor"
		, "set -e"
		, "pass=$HOME/.pine-password"
		, "if [ ! -e $pass ]; then"
		, "\ttouch $pass"
		, "fi"
		, "chmod 600 $pass"
		, "exec alpine -passfile $pass \"$@\""
		]
		`onChange` (pinescript `File.mode`
			combineModes (readModes ++ executeModes))
		`describe` "pine wrapper script"
	, "/etc/pine.conf" `File.containsLines`
		[ "inbox-path={localhost/novalidate-cert}inbox"
		]
		`describe` "pine configured to use local imap server"
	]
  where
	ctx = Context "kitenet.net"
	pinescript = "/usr/local/bin/pine"
	dovecotusers = "/etc/dovecot/users"

hasJoeyCAChain :: Property
hasJoeyCAChain = "/etc/ssl/certs/joeyca.pem" `File.hasPrivContentExposed`
	Context "joeyca.pem"
