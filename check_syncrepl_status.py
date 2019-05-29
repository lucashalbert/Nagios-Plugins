#!/usr/bin/env python

#
# Script to check LDAP syncrepl replication state between two servers.
# One server is consider as provider and the other as consumer.
#
# This script can check replication state with two method :
#  - by the fisrt, entryCSN of all entries of LDAP directory will be
#    compare between two servers
#  - by the second, all values of all atributes of all entries will
#    be compare between two servers.
# In all case, contextCSN of servers will be compare and entries not
# present in consumer or in provider will be notice.
#
# This script could be use as Nagios plugin (-n argument)
#
# Requirement : 
# A single couple of DN and password able to connect to both server 
# and without restriction to retrieve objects from servers.
#     
# Author : Benjamin Renard <brenard@easter-eggs.com>
# Date : Mon, 10 Dec 2012 18:04:24 +0100
# Source : http://git.zionetrix.net/check_syncrepl_extended
#
# Modified By: Lucas halbert <lhalbert@lhalbert.xyz>
# Date Modified: 05/07/2018
# Modified Source : https://github.com/lucashalbert/Nagios-Plugins
# Modification Description: Removed the requirement for authenticated
#                           BINDs. Add the ability to enter password
#                           at runtime.
#

import ldap
import logging
import sys
import getpass

from optparse import OptionParser

parser = OptionParser(version="%prog version 1.0\n\nDate : Mon, 10 Dec 2012 18:04:24 +0100\nAuthor : Benjamin Renard <brenard@easter-eggs.com>\nSource : http://git.zionetrix.net/check_syncrepl_extended")

parser.add_option(	"-p", "--provider",
			dest="provider",
			action="store",
			type='string',
        		help="LDAP provider URI (example : ldaps://ldapmaster.foo:636)")

parser.add_option(	"-c", "--consumer",
			dest="consumer",
			action="store",
			type='string',
        		help="LDAP consumer URI (example : ldaps://ldapslave.foo:636)")

parser.add_option(	"-D", "--dn",
			dest="dn",
			action="store",
			type='string',
        		help="LDAP bind DN (example : uid=nagios,ou=sysaccounts,o=example")

parser.add_option(	"-P", "--pwd",
			dest="pwd",
			action="store",
			type='string',
        		help="LDAP bind password")

parser.add_option(	"-b", "--basedn",
			dest="basedn",
			action="store",
			type='string',
        		help="LDAP base DN (example : o=example)")

parser.add_option(	"-f", "--filter",
			dest="filter",
			action="store",
			type='string',
        		help="LDAP filter (default : (objectClass=*))",
			default='(objectClass=*)')

parser.add_option(	"-d", "--debug",
			dest="debug",
			action="store_true",
        		help="Debug mode",
			default=False)

parser.add_option(	"-n", "--nagios",
			dest="nagios",
			action="store_true",
        		help="Nagios check plugin mode",
			default=False)

parser.add_option(	"-q", "--quiet",
			dest="quiet",
			action="store_true",
        		help="Quiet mode",
			default=False)

parser.add_option(	"--no-check-certificate",
			dest="nocheckcert",
			action="store_true",
        		help="Don't check the server certificate (Default : False)",
			default=False)

parser.add_option(	"--no-check-contextCSN",
			dest="nocheckcontextcsn",
			action="store_true",
        		help="Don't check servers contextCSN (Default : False)",
			default=False)

parser.add_option(	"-a", "--attributes",
			dest="attrs",
			action="store_true",
        		help="Check attributes values (Default : check only entryCSN)",
			default=False)

(options, args) = parser.parse_args()

if not options.provider or not options.consumer:
	print "You must provide provider and customer URI"
	sys.exit(1)

#if not options.dn or not options.pwd:
#    if not options.pwd:
#        options.pwd = getpass.getpass("Enter DN Password: ");
#
#    if not options.dn:
#	    print "You must provide DN and password to connect to LDAP servers"
#	    sys.exit(1)

if options.dn and not options.pwd:
    print "You must provide a DN password to connect to LDAP servers"
    options.pwd = getpass.getpass("Enter DN Password: ");

if not options.basedn:
	print "You must provide base DN of connection to LDAP servers"
	sys.exit(1)

FORMAT="%(asctime)s - %(levelname)s : %(message)s"

if options.debug:
	logging.basicConfig(level=logging.DEBUG,format=FORMAT)
	ldap.set_option(ldap.OPT_DEBUG_LEVEL,0)
	ldapmodule_trace_level = 1
	ldapmodule_trace_file = sys.stderr
elif options.nagios:
	logging.basicConfig(level=logging.ERROR,format=FORMAT)
elif options.quiet:
	logging.basicConfig(level=logging.WARNING,format=FORMAT)
else:
	logging.basicConfig(level=logging.INFO,format=FORMAT)

class LdapServer(object):

        uri = ""
        dn = ""
        pwd = ""

        con = 0

        def __init__(self,uri,dn,pwd):
                self.uri = uri
                self.dn   = dn
                self.pwd  = pwd

        def connect(self):
                if self.con == 0:
                        try:
                                con = ldap.initialize(self.uri)
                                con.protocol_version = ldap.VERSION3
                                if self.dn != '':
                                    if not self.dn and not self.pwd:
                                        con.simple_bind_s()
                                    else:
                                        con.simple_bind_s(self.dn,self.pwd)
                                self.con = con
				return True
                        except ldap.LDAPError, e:
                                logging.error("LDAP Error : %s" % e)
				return

	def getContextCSN(self,basedn):
		data=self.search(basedn,'(objectclass=*)',['contextCSN'])
		if len(data)>0:
			return data[0][0][1]['contextCSN'][0]
		else:
			return False

        def search(self,basedn,filter,attrs):
                res_id = self.con.search(basedn,ldap.SCOPE_SUBTREE,filter,attrs)
                ret = []
                while 1:
                        res_type, res_data = self.con.result(res_id,0)
                        if res_data == []:
                                break
                        else:
                                if res_type == ldap.RES_SEARCH_ENTRY:
                                        ret.append(res_data)
                return ret

if options.nocheckcert:
	ldap.set_option(ldap.OPT_X_TLS_REQUIRE_CERT,ldap.OPT_X_TLS_NEVER)

servers=[options.provider,options.consumer]

LdapServers={}
LdapObjects={}
LdapServersCSN={}

for srv in servers:
	logging.info('Connect to %s' % srv)
	LdapServers[srv]=LdapServer(srv,options.dn,options.pwd)

	if not LdapServers[srv].connect():
		if options.nagios:
			print "UNKNOWN - Failed to connect to %s" % srv
			sys.exit(3)
		else:
			sys.exit(1)

	if not options.nocheckcontextcsn:
		LdapServersCSN[srv]=LdapServers[srv].getContextCSN(options.basedn)
		logging.info('ContextCSN of %s : %s' % (srv, LdapServersCSN[srv]))

	logging.info('List objects from %s' % srv)
	LdapObjects[srv]={}

	if options.attrs:
		for obj in LdapServers[srv].search(options.basedn,options.filter,[]):
			logging.debug('Found on %s : %s' % (srv,obj[0][0]))
			LdapObjects[srv][obj[0][0]]=obj[0][1]
	else:
		for obj in LdapServers[srv].search(options.basedn,options.filter,['entryCSN']):
			logging.debug('Found on %s : %s / %s' % (srv,obj[0][0],obj[0][1]['entryCSN'][0]))
			LdapObjects[srv][obj[0][0]]=obj[0][1]['entryCSN'][0]

	logging.info('%s objects founds' % len(LdapObjects[srv]))


not_found={}
not_sync={}

for srv in servers:
	not_found[srv]=[]
	not_sync[srv]=[]

if options.attrs:
	logging.info("Check if objects a are synchronized (by comparing attributes's values)")
else:
	logging.info('Check if objects are synchronized (by comparing entryCSN)')
for obj in LdapObjects[options.provider]:
	logging.debug('Check obj %s' % (obj))
	for srv in LdapObjects:
		if srv == options.provider:
			continue
		if obj in LdapObjects[srv]:
			if LdapObjects[options.provider][obj] != LdapObjects[srv][obj]:
				if options.attrs:
					attrs_list=[]
					for attr in LdapObjects[options.provider][obj]:
						if attr not in LdapObjects[srv][obj]:
							attrs_list.append(attr)
						elif LdapObjects[srv][obj][attr]!=LdapObjects[options.provider][obj][attr]:
							attrs_list.append(attr)
					logging.debug("Obj %s not synchronized : %s" % (obj,','.join(attrs_list)))
					not_sync[srv].append("%s (%s)" % (obj,','.join(attrs_list)))
				else:
					logging.debug("Obj %s not synchronized : %s <-> %s" % (obj,LdapObjects[options.provider][obj],LdapObjects[srv][obj]))
					not_sync[srv].append(obj)
		else:
			logging.debug('Obj %s : not found on %s' % (obj,srv))
			not_found[srv].append(obj)

for obj in LdapObjects[options.consumer]:
	logging.debug('Check obj %s of consumer' % obj)
	if obj not in LdapObjects[options.provider]:
		logging.debug('Obj %s : not found on provider' % obj)
		not_found[options.provider].append(obj)

if options.nagios:
	errors=[]

	if not options.nocheckcontextcsn:
		for srv in LdapServersCSN:
			if srv==options.provider:
				continue
			if LdapServersCSN[srv]!=LdapServersCSN[options.provider]:
				errors.append('ContextCSN of %s not the same of provider' % srv)

	if len(not_found[options.consumer])>0:
		errors.append("%s not found object(s) on consumer" % len(not_found[options.consumer]))
	if len(not_found[options.provider])>0:
		errors.append("%s not found object(s) on provider" % len(not_found[options.provider]))
	if len(not_sync[options.consumer])>0:
		errors.append("%s not synchronized object(s) on consumer" % len(not_sync[options.consumer]))
	if len(errors)>0:
		print "CRITICAL : "+', '.join(errors)
		sys.exit(2)
	else:
		print 'OK : consumer and provider are synchronized'
		sys.exit(0)
else:
	noerror=True
	for srv in servers:
		if len(not_found[srv])>0:
			logging.warning('Not found objects on %s :\n  - %s' % (srv,'\n  - '.join(not_found[srv])))
			noerror=False
		if len(not_sync[srv])>0:
			logging.warning('Not sync objects on %s : %s' % (srv,'\n  - '.join(not_sync[srv])))
			noerror=False
	
	if noerror:
		logging.info('No sync problem detected')
