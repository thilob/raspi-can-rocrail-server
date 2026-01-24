Mit folgender Zeile wird Rocrail automatisch gestartet:

<code>
# m h  dom mon dow   command
@reboot ~/Rocrail/startrocrail.sh
</code>

Die Zeile muss per 

<code>
crontab -e
</code>

in die Crontabelle eingetragen werden.
