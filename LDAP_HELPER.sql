create schema IF NOT EXISTS EXA_TOOLBOX;
open schema EXA_TOOLBOX;
'''
###############################################
#-------------- NOTES for Usage --------------#
###############################################
-----------------------------------------------
EXECUTION_MODE options: DEBUG or EXECUTE. In debug mode, all queries are rolled back
 ----------------------------------------------
  This script will help you explore ldap attributes. This is helpful when you do not know which attributes contain the role members or the username
  
  1) To find out which attributes contain the group members, you can run this: select EXA_TOOLBOX.LDAP_HELPER('LDAP_SERVER', ROLE_COMMENT) from exa_Dba_roles where role_name = <role name>
  
  2) To find out which attributes contain the username, you can run this: select EXA_TOOLBOX.LDAP_HELPER('LDAP_SERVER', user_name) from exa_dba_connections WHERE connection_name = 'LDAP_SERVER'; 
  
  3) For other purposes, you can run the script using the LDAP connection you created and the distinguished name of the object you want to investigate: SELECT EXA_TOOLBOX.LDAP_HELPER(<LDAP connection>,<distinguished name>);

###############################################
--------------- General READ ME  --------------
###############################################
Note: This release is now PYTHON3

Purpose: This script is designed to extract LDAP information.
About:   This version of the script underwent a refactoring and was upgraded to Python3.       

What is new in this version?
--------------------------------------------
1. Added additional tests to validate the Connnection.
---------------------------------------------
  This script will end abnormally if a valid LDAP connection can not be made. Primarily,
  this will aid troubleshooting when doing a first time implentation of the LDAP Sync
  (think firewalls and forgetting to set the "LDAP Server URLS" in EXAOperation).
      This script is now more aggessive with validations and no longer passively returns
  if valid LDAP data is not extracted, unless it is intentional. We added socket
  processing to assist in validating CONNECTIONS. 
---------------------------------------------
2. Conversion to Python3 includes:
---------------------------------------------
   a. Changes in handling string and byte datatypes. There are differences between 
   Python2 and Python3. What used to work in Python2 no longer works as-is in Python3.
   b. Accounting for new error message formats in Python3.
---------------------------------------------
3. Add additional documentation
---------------------------------------------
   To improve user experience with first time implementation
   and troubleshooting.
'''
--
-- Example of valid LDAP connection
--
--create or replace connection test_ldap_server to 'ldap://192.168.1.155:389' user 'cn=admin,dc=manhlab,dc=com' identified by 'abc';

--/
CREATE OR REPLACE PYTHON3 SCALAR SCRIPT "LDAP_HELPER" ("LDAP_CONNECTION" VARCHAR(2000),"SEARCH_STRING" VARCHAR(2000) UTF8) 
EMITS ("SEARCH_STRING" VARCHAR(2000) UTF8, "ATTR" VARCHAR(1000), "VAL" VARCHAR(1000) UTF8)  AS
import ldap
import socket    # To test LDAP connectivity and abnormally end if LDAP server is not reachable.
                 # Basically, is the connection to the LDAP Server blocked by unknown firewall
            
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Script Variables
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
results = ''
encoding  = 'utf-8'
abortMessage = ">>> Aborting with no action taken!"
server =''
port=-1
url_components = ['.',':']  # When validating the Host URL, we are looking for IP addr or www.example.com
                            #   (the "." period) or IPV6 with colons.
ldap_prefix  = "://"        # The :// in ldap://
result=[]
#########################################
# FUNCTIONS
#########################################
#----------------------------------------
def extract_host(ldap_server):
#----------------------------------------

    try:
        ldap_server = str(ldap_server)          # Make ldap_serve  string object
        server = ldap_server.split(":")         # Elliminate prefix "ldap" om the conection string,Server is now a list without the ":" characters
        if len(server) > 1:
            if len(server) == 3:
                global port
                assert(isinstance(port, int))
                port = int(server[2])
            if ldap_prefix.find(server[1]):
                server = server[1].replace('//','')
    except Exception as e:
        raise Exception(f"Error, unable to parse valid values {server}, Port: {port} from LDAP Entry:", ldap_server, (str(e), abortMessage))
        
    try:
        assert(port > 0)
    except Exception as e:
        raise Exception(f"Error,Port <1. We have Port {port} from LDAP Entry:", ldap_server, (str(e), abortMessage))
    
    return server, int(port)
#######################################
# BEGIN LOGIC
#######################################
def run(ctx):
#-------------------------------------
    #=====================================
    # Housekeeping - define and validate variables used in MAIN LOGIC section
    #=====================================
    '''
    The below information corresponds to the user needed to connect to ldap who can traverse the ldap structure and pull out user attributes. 
    1) This information should be stored in a CONNECTION object and you must GRANT ACCESS ON <CONNECTION> FOR <SCRIPT> TO <USER>
    2) More details: https://docs.exasol.com/database_concepts/udf_scripts/hide_access_keys_passwords.htm
    '''
    #----------------------------------------
    # Ensure Connection String has a proper LDAP server
    #----------------------------------------
    try:
        uri = exa.get_connection(ctx.LDAP_CONNECTION).address
        ldap_server = uri
    except Exception as e:
        raise Exception("Unable to find/parse exa.get_connection(ctx.LDAP_CONNECTION).address", exa.meta.script_name, (str(e), abortMessage))   

    server, port = extract_host(ldap_server)
    
    #----------------------------------------
    # Validate just the port extraced from the LDAP CONNECTION
    #----------------------------------------
    try:
        if isinstance(port, int) and (port > 0):
            pass
        else:
            raise Exception(f"Error, trying to validate a numeric Port NUMBER returned: {port} -- from LDAP CONNECTION entry", ldap_server)
    except Exception as e:
        raise Exception("Error, unable to extract valid values for the PORT as found in the LDAP Entry:", ldap_server, (str(e), abortMessage))
    
          
    #----------------------------------------
    # Start building a socket to then test the Host and port for reachability
    #----------------------------------------
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    except Exception as e:
        raise Exception("Unable to open socket", exa.meta.script_name, (str(e), abortMessage))
    
    #----------------------------------------
    # Set socket to timeout after 30 seconds
    #----------------------------------------
    try:
        sock.settimeout(30)
    except Exception as e:
        raise Exception("Unable to set socket timeout", exa.meta.script_name, (str(e), abortMessage))

    #----------------------------------------
    # Make socket connection to LDAP Host and port
    #----------------------------------------
    try:
        global result
        result = sock.connect_ex((server, port))
    except Exception as e:
        if result == 11:
            raise Exception("Socket timeout...unable to connect to " + str(server) + " and port " + str(port), exa.meta.script_name, (str(e), abortMessage))
        else:
            raise Exception("Can open socket, but unable to connect to " + str(server) + " and port " + str(port), exa.meta.script_name, (str(e), abortMessage))
    
    #----------------------------------------
    # If result is anything but 0, then the port was not available
    #----------------------------------------
    try:
        if int(result):
            raise Exception("Either the host " + str(server) + " is not reachable or Port " + str(port) + " is not reachable on " + server, exa.meta.script_name)
    except Exception as e:
        raise Exception("From socket connection on host " + server + " port " + str(port) + " did not work", exa.meta.script_name, (str(e), abortMessage))
        
    #========================================
    # House Keeping - Validate remaining Connection properties
    #========================================
    try:
        user = exa.get_connection(ctx.LDAP_CONNECTION).user        #technical user for LDAP
    except Exception as e:
        raise Exception("Unable to find/parse exa.get_connection(ctx.LDAP_CONNECTION).user", exa.meta.script_name, (str(e), abortMessage))
        
    try:
        password = exa.get_connection(ctx.LDAP_CONNECTION).password    #pwd of technical user
    except Exception as e:
        raise Exception("Unable to find/parse exa.get_connection(ctx.LDAP_CONNECTION).password", exa.meta.script_name,(str(e), abortMessage))
        
    try:
        encoding = 'utf-8'  #may depend on ldap server, try latin1 or cp1252 if you get problems with special characters
    except Exception as e:
        raise Exception("Unable to set encoding = utf-8", exa.meta.script_name, (str(e), abortMessage))
    
    #========================================
    # Begin LDAP interaction
    #========================================  
    try:
        ldapClient = ldap.initialize(uri)   # Connects to LDAP
    except Exception as e:
        raise Exception("Ldap initialization failed. Check the uri from uri = exa.get_connection(ctx.LDAP_CONNECTION).address #ldap/AD server" , exa.meta.script_name, (str(e), abortMessage))

    #----------------------------------------
    # Sets a timeout of 5 seconds to connect to LDAP
    #----------------------------------------
    try:
        ldapClient.set_option(ldap.OPT_NETWORK_TIMEOUT, 5.0)
    except Exception as e:
	        raise Exception("Failure on ldapClient set_option(ldap.OPT_NETWORK_TIMEOUT, 5.0)", exa.meta.script_name, (str(e), abortMessage))
        
    #----------------------------------------
	# The below line is only needed when connecting via ldaps
	#----------------------------------------
    try:
        ldapClient.set_option(ldap.OPT_X_TLS_REQUIRE_CERT, ldap.OPT_X_TLS_NEVER)   # required options for SSL without cert checking
    except Exception as e:
        raise Exception("Failed! ldapClient.set_option(ldap.OPT_X_TLS_REQUIRE_CERT, ldap.OPT_X_TLS_NEVER", exa.meta.script_name,  (str(e), abortMessage))
        
#######################################
# MAIN LOGIC
#######################################

    #----------------------------------------
    # Authenticates with connection credentials
    #----------------------------------------
    try:
        ldapClient.bind_s(user, password)
    except Exception as e:
	    raise Exception(f"Failed: ldapClient.bind_s(user, password) for user {user}" , exa.meta.script_name, (str(e), abortMessage))
	    
	#---------------------------------------
    # Python 3 can not handle bytes, so we decode to chg bytes to string
    #---------------------------------------  
    try:
        global results
        results = ldapClient.search_s(str(ctx.SEARCH_STRING.encode(encoding).decode('utf-8')), ldap.SCOPE_BASE)
    except Exception as e:
        not_found = 'No such object'
        if not_found.find(str(e)):
            ctx.emit(ctx.SEARCH_STRING, 'CN not found', 'No such object')
        else:
            raise Exception("ldapClient.search failed: results with error={0}".format(e), exa.meta.script_name, (str(e), abortMessage))
        
    #----------------------------------------
    # Prepare results for display and return results if called from Lua Script.
    # Execute the LDAP unbind regardless of outcome.
    #----------------------------------------
    try:
        for result in results:     # Emits the results of the specified attributes
            result_dn    = result[0]
            result_attrs = result[1]
            for attrs in result_attrs:
                for y in result_attrs[attrs]:
                    y = str(bytes(y).decode('utf-8'))
                    ctx.emit(result_dn, attrs, str(y))
    except Exception as e:
        print(e)
        not_found = 'No such object'
        if not_found.find(str(e)):
            ctx.emit(ctx.SEARCH_STRING, 'DN not found', 'No such object')
        else:
            raise Exception(ldap.LDAPError(e))
    finally:
        ldapClient.unbind_s()		     

/
---------------------------------------
-- MAIN SCRIPT Example (Don't forget to "open" the schema, first)
---------------------------------------
--
--select LDAP_HELPER('TEST_LDAP_WEB', ROLE_COMMENT)  from exa_Dba_roles where role_name = 'AM';
--
