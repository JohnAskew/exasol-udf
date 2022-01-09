CREATE SCHEMA IF NOT EXISTS EXA_TOOLBOX;
OPEN SCHEMA EXA_TOOLBOX

--/
CREATE OR REPLACE PYTHON SCALAR SCRIPT MAIL_MAN (summary varchar(200000)) 
emits (message varchar(1000))
AS
import smtplib
from email.mime.text import MIMEText
import datetime as dt
#######################################
# FUNCTIONS
#######################################
#---------------------------------------
def get_timestamp():
#---------------------------------------
    now = dt.datetime.now()
    now_formatted = now.strftime("%Y-%m-%d %H.%M")
    return now_formatted

#---------------------------------------
def parse_summary(summaries):
#---------------------------------------
    s = ''
    cr = "\n"
    for sum in summaries:
        #ctx.emit(sum)
        s +=sum
        s +=cr
    return s

#######################################
# MAIN LOGIC
#######################################

#---------------------------------------
def run(ctx):
#---------------------------------------
    summaries = ctx.summary.split("'")
    summaries = [sum.strip(",") for sum in summaries if sum != ' ']
    s = parse_summary(summaries)
    print(s)
    
    date_now = get_timestamp()
    #-----------------------------------
    # Begin example mail code.
    # Be sure and add the variable "s" to the body.
    # This has been done for you, see the line: "body +=s"
    #-----------------------------------
    # Mail server credentials
    #-----------------------------------
    mail_user = 'yourmailuser@example.com'
    mail_password = 'yourmailpassword'
    #-----------------------------------
    # Mail content
    #-----------------------------------
    sent_from = 'jane.doe@example.com'
    to = ['exa-john@exasol.com']
    subject = 'LDAP Sync Report'
    body = "Reporting for {}\n".format(get_timestamp())
    body += s

    email_text = """From: %s\nTo: %s\nSubject: %s\n\n%s""" % (sent_from, ", ".join(to), subject, body)
    try:
        server = smtplib.SMTP_SSL('smtp.example.com', 465)
        server.ehlo()
        server.login(mail_user, mail_password)
        server.sendmail(sent_from, to, email_text)
        server.close()
        print 'Email sent!'
    except:
        ctx.emit('Something is not working')
/