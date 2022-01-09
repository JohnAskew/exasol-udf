create schema if not exists EXA_TOOLBOX;
open schema EXA_TOOLBOX;
--This script will search for the specified attribute on the given distinguished name
--
-- Example of valid LDAP connection
--
--create or replace connection test_ldap_server to 'ldap://192.168.1.155:389' user 'cn=admin,dc=manhlab,dc=com' identified by 'abc';

--/
CREATE OR REPLACE PYTHON3 SCALAR SCRIPT "GET_AD_ATTRIBUTE" ("LDAP_CONNECTION" VARCHAR(2000),"SEARCH_STRING" VARCHAR(2000) UTF8, "ATTR"  VARCHAR(1000),  "VERIFY" VARCHAR(10)) 
EMITS ("SEARCH_STRING" VARCHAR(2000) UTF8, "ATTR" VARCHAR(1000), "VAL" VARCHAR(1000) UTF8) AS
'''
###############################################
--------------- General READ ME  --------------
###############################################
Note: This release is now PYTHON3

Purpose: This script is designed to extract LDAP information.
About:   This version of the script underwent a refactoring and was upgraded to Python3.       

What is new in this version
--------------------------------------------
1. Added additional tests to validate the Connnection.
---------------------------------------------
  This script will end abnormally if a valid LDAP connection can not be made. Primarily,
  this will aid troubleshooting when doing a first time implentation of the LDAP Sync
  (think firewalls and forgetting to set the ldap parameter in EXAOperation).
      This script is now more aggessive with validations and no longer passively returns
  if valid LDAP data is not extracted, unless it is intentional.
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

import ldap
import socket           # To test LDAP connectivity and abnormally end if LDAP server is not reachable.
                        # Do not return to calling script with null results (actually empty string)
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Script Variables
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
DEBUG = False               # Flag to scrutinize the CONNECTION
results = ''                # Here is my empty string for storing LDAP data
connect_result = ''         # Hold sock.connect_ex results
abortMessage = ">>> Aborting with no action taken!"
ldap_server =''             # Variable holding the input of ctx.LDAP_CONNECTION
server = ''                 # Variable holding the extracted LDAP Server address
port = 'null'               # Variable holding the extract LDAP Port
uri=''                      # Varaible to hold input URI (url)
colon = ":"                 #IPv4 / DNS variable containing a colon
ipVersion4 = False          # Socket criteria using ipv4 address
ipVersion6 = False          # Socket criteria using ipv6 address
url_components = ['.',':']  # When validating the Host URL, we are looking for IP addr or www.example.com
                            #      (the "." period) or IPV6 with colons.
ldap_prefix  = ":\/\/"        # The connection element just before the actual LDAP Server address`
my_socket_addr_list = []    # Will use this is resolving address with socket.getaddrinfo
#######################################
# FUNCTIONS
#######################################
def validate_connection(ldap_server:str(500)) -> None:
#--------------------------------------
    #----------
    # Simplistic, but catches issue with core functionality
    #----------
    try:
        if len(ldap_server) == 0:
           raise ValueError(f"The incoming LDAP CONNECTION has invalid or missing data. The LDAP CONNECTION used was parsed into -->: '{ldap_server}'.")
    except Exception as e:
        raise ValueError("Script found an empty LDAP entry of:", ldap_server, (str(e), abortMessage))
    
    #----------
    # First, did my CONNECTION start with "ldap", as in ldap: or ldaps:
    #----------
    try:
        if ldap_server.upper()[0:4] != "LDAP":
            raise Exception(f"The CONNECTION provided {ldap_server} did not start with 'ldap'")
    except Exception as e:
        raise Exception(f"Unable to use ldap connection provided: {ldap_server}", exa.meta.script_name, (str(e), abortMessage))
    
    #----------
    # Parse port`
    #----------
    try:
        global port
        port = (ldap_server[(ldap_server.rindex(colon)+1):])
    except Exception as e:
        raise Exception(f"Error, unable to extract the  port '{port}', taken from the last ':' element in the  LDAP entry:", ldap_server, str(e), abortMessage)
        
    #----------
    # Continue editting port
    # Valid ports are 1:65535. Hence, if length port > 5 - we have unusable port
    #----------
    
    try:
        if len(str(port)) == 0 or (len(str(port)) > 5 ):
            raise Exception(f"Error, Port is missing or provided port is invalid, example of what we are expecting: 'ldap://192.168.2.155:389'. Trying to extract the port as the last element in the CONNECTION, we receieved this--> '{port}'. It's not a valid port nunber > 0, taken from the last ':' element in the  LDAP entry:",ldap_server)
    except Exception  as e:
        raise Exception(f"Error, from from the last ':' element, we expected the port in the form :389, where 389 is the actual LDAP port number. The LDAP entry provided was:",ldap_server, str(e), abortMessage)
    
    #----------
    # Edit port for being an integer and positive value > 0
    #----------    
    
    try:
        if port.isnumeric():
            port = int(port)
        else:
            raise ValueError(f"The port provided --> {port} <-- is not a valid number. The port is taken from the last element in ", ldap_server)
    except Exception as e:
        raise Exception(f"Error, the parsed port '{port}' is not a valid number > 0, taken from the last ':' element in the  LDAP entry: appears to be reading the ldap server string.", ldap_server, str(e), abortMessage)
    
    #----------
    # Parse the host
    #----------
    try:
        global server
        server = ldap_server[ldap_server.index(colon)+1:ldap_server.rindex(str(port))-1]
        server = str(server)
        if (len(server) > 1):
            if ldap_prefix.find(server[1]):
                server = server.replace('//','')
    except Exception as e:
        raise Exception(f"Error, unable to parse valid values {server}, Port: {port} from LDAP Entry:", ldap_server, str(e), abortMessage)

    #----------------------------------------
    # Validate just the server (host) extraced from the LDAP CONNECTION.
    #     Look for periods in I.P. address or DSN address, 
    #     look for colon in IPv6 address
    #----------------------------------------
    
    try:
        if [comp for comp in url_components if comp.find(str(server))]:
            pass
        else:
            raise Exception("Error, unable to extract valid values for the HOST as found in the LDAP Entry:", ldap_server, str(e), abortMessage)
    except Exception as e:
        raise Exception("Failed! server does not contain valid values for the HOST as found in the LDAP Entry:", ldap_server, str(e), abortMessage)
    
    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # Are we using IPv6 or IPv4
    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~   
    try:
        my_socket_addr_list = list(socket.getaddrinfo(server, port, 0,0, socket.SOL_TCP))
    except Exception as e:
        raise Exception(f" Are you using DNS in the LDAP CONNECTION servername? Maybe try using I.P.address, as we have an unknown LDAP host, when using socket.getaddrinfo for server {server}, port {port} taken from the provided connection",  ldap_server , str(e), abortMessage)
    
    #----------
    ''' Extract getaddrinfo into a usable list - just the ip and port info returned
        ** Note (my_tuple[4]) contains the returned server_name
        The end game is to verify the CONNECTION is using an ipv4 address.
        We currently do not support IPv6 - and it requires different socket arguments.''' 
    #----------
    
    addr_list = []
    try:
        for my_tuple in my_socket_addr_list:
            addr_list.append(my_tuple)
    except Exception as e:
        raise Exception(f"Unable to parse my_socket_addr_list into a list. addr_list=" + str(addr_list) + " from ldap_server entry: ", ldap_server, str(e), abortMessage)
        
    #----------
    # Parse the addr_list that contained the socket.getaddrinfo response.
    #----------
    ip_info = str(addr_list[0])
    ipVersion6 = ip_info.find('AddressFamily.AF_INET6:')
    if ipVersion6 == 2:
        ipVersion6 = True
    else:
        ipVersion6 = False
        
    ipVersion4 = ip_info.find('AddressFamily.AF_INET:')
    if ipVersion4 == 2:
        ipVersion4 = True
    else:
        ipVersion4 = False

    #----------------------------------------
    # Start building a socket to then test the Host and port for reachability
    #----------------------------------------
    try:
        if ipVersion4:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
        else:
            raise Exception(f"Failed defining our socket using {server}, as currently we only support IPv4")
    except Exception as e:
            raise Exception("Unable to build socket", exa.meta.script_name, str(e), abortMessage)
    
    #----------------------------------------
    # Set socket to timeout after 30 seconds
    #----------------------------------------
    try:
        sock.settimeout(30)
    except Exception as e:
        raise Exception("Unable to set socket timeout", exa.meta.script_name, str(e), abortMessage)
    
    #----------------------------------------
    # Make socket connection to LDAP Host and port
    #----------------------------------------
    try:
        global connect_result
        connect_result = sock.connect_ex((str(server), port))
    except Exception as e:
        if result == 11:
            raise Exception("Socket timeout...unable to connect to " + str(server) + " and port " + str(port), exa.meta.script_name, (str(e), abortMessage))
        else:
            raise Exception("Can open socket, but unable to connect to " + str(server) + " and port " + str(port), exa.meta.script_name, (str(e), abortMessage))
    
    #----------------------------------------
    # If connect_result is anything but 0, then the port was not available
    #----------------------------------------
    try:
        if (int(connect_result) > 0):
            raise Exception("Either the host " + str(server) + " is not reachable or Port " + str(port) + " is not reachable on " + server, exa.meta.script_name)
    except socket.error:
        raise Exception(f"Socket connect returned: {connect_result}.", exa.meta.script_name, (str(socket.error), abortMessage))
    except Exception as e:
        raise Exception(f"Results from socket connection on host " + server + " port " + str(port) + " did not work; Return_code {}".format(connect_result), exa.meta.script_name, (str(e), abortMessage))


#######################################
# BEGIN LOGIC
#######################################
def run(ctx):
    #=======================================
    # House Keeping - Validate LDAP Host Connection 
    #========================================
    print("Hello World")
    
    if ctx.VERIFY.upper() == 'DEBUG':
        DEBUG = 1
    else:
        DEBUG = 0
    
    #----------
    # Ensure Connection String has a proper LDAP server
    #----------
    global uri
    try:
        uri = exa.get_connection(ctx.LDAP_CONNECTION).address
        ldap_server = str(uri)
    except Exception as e:
        raise Exception(f"Unable to find/parse {uri} from the exa.get_connection(ctx.LDAP_CONNECTION).address. Error caught in:", exa.meta.script_name, str(e), abortMessage)
    
    if DEBUG:
        validate_connection(ldap_server)
        
    

    #========================================
    # House Keeping - Validate remaining Connection properties
    #========================================
    try:
        user = exa.get_connection(ctx.LDAP_CONNECTION).user        #technical user for LDAP
    except Exception as e:
        raise Exception("Unable to find/parse exa.get_connection(ctx.LDAP_CONNECTION).user", exa.meta.script_name, str(e), abortMessage)
        
    try:
        password = exa.get_connection(ctx.LDAP_CONNECTION).password    #pwd of technical user
    except Exception as e:
        raise Exception("Unable to find/parse exa.get_connection(ctx.LDAP_CONNECTION).password", exa.meta.script_name, str(e), abortMessage)
        
    try:
        encoding = "utf8"  #may depend on ldap server, try latin1 or cp1252 if you get problems with special characters
    except Exception as e:
        raise Exception("Unable to set encoding = utf8", exa.meta.script_name, str(e), abortMessage)
    
    #----------------------------------------
    # Sets a network timeout of 15 seconds to connect to LDAP
    #----------------------------------------
    try:
        ldap.set_option(ldap.OPT_NETWORK_TIMEOUT, 30.0)
    except Exception as e:
	    raise Exception("Failure on ldap.set_option(ldap.OPT_NETWORK_TIMEOUT, 5.0)", exa.meta.script_name, str(e), abortMessage)
	
	#----------------------------------------
	# The below line is only needed when connecting via ldaps
	#----------------------------------------
    try:
        ldap.set_option(ldap.OPT_X_TLS_REQUIRE_CERT, ldap.OPT_X_TLS_NEVER)   # required options for SSL without cert checking
    except Exception as e:
        raise Exception("Failed! ldap.set_option(ldap.OPT_X_TLS_REQUIRE_CERT, ldap.OPT_X_TLS_NEVER", exa.meta.script_name,  str(e), abortMessage)
        
    #========================================
    # Begin LDAP interaction
    #========================================  
    try:
        ldapClient = ldap.initialize(uri)   # Connects to LDAP
    except Exception as e:
        raise Exception(f"Ldap initialization failed. Check the uri from uri = {uri}" , exa.meta.script_name, str(e), abortMessage)
    

        
#######################################
# MAIN LOGIC
#######################################

    #----------------------------------------
    # Authenticates with connection credentials
    #----------------------------------------
    try:
        ldapClient.bind_s(user, password)
    except Exception as e:
	        raise Exception(f"Failed: ldapClient.bind_s(user, password) for user {user}" , exa.meta.script_name, str(e), abortMessage)
	    
    #---------------------------------------
    # Python 3 can not handle bytes, so we decode to chg bytes to string
    #---------------------------------------  
    try:
        global results
        results = ldapClient.search_s(ctx.SEARCH_STRING.encode(encoding).decode('utf-8'), ldap.SCOPE_BASE)
    except Exception as e:
        not_found = 'No such object'
        invalid_dn = 'invalid DN'
        if not_found.find(str(e)):
            ctx.emit(ctx.SEARCH_STRING, ctx.ATTR, 'No such object')
        elif invalid_dn.find(str(e)):
            raise Exception("ldapClient.search failed: results with error={0}".format(e), exa.meta.script_name, ("Exasol ROLE with comment " + ctx.SEARCH_STRING + " is NOT found on LDAP Server."))
        else:
            raise Exception("ldapClient.search failed: results with error={0}".format(e), exa.meta.script_name, (str(e), abortMessage))
     
    #----------------------------------------
    # Prepare results for display and return results if called from Lua Script.
    # Execute the LDAP unbind regardless of outcome.
    #----------------------------------------     
    try:
        # Emits the results of the specified attributes
        for result in results:
            result_dn = result[0]
            result_attrs = result[1]
            if ctx.ATTR in result_attrs:
                [ctx.emit(ctx.SEARCH_STRING, ctx.ATTR, v.decode('utf-8')) for v in result_attrs[ctx.ATTR]]
    except Exception as e:
        not_found = 'No such object'
        if not_found.find(str(e)):
            ctx.emit(ctx.SEARCH_STRING, ctx.ATTR, 'No such object')
        else:
            raise Exception(ldap.LDAPError(e))
    finally:
        ldapClient.unbind_s()		

/
---------------------------------------
-- MAIN SCRIPT Example. (Don't forget to "open" the schema, first)
---------------------------------------
--
-- New version 2.2
--
--select GET_AD_ATTRIBUTE('TEST_LDAP_WEB','cn=Joshua Smith,ou=Users,dc=manhlab,dc=com', 'uid','DEBUG');

