# Rättigheter i Linux och Windows

Uppgiften säger att rapporten ska "tydligt analysera skillnaderna i hur
operativsystemen hanterar användarrättigheter, arv och filsystemssäkerhet".
Den här texten gör det med tre skillnader. Jämförelsen bygger på
samma struktur i båda systemen: mappen Projekt med Gemensamt och Ledning,
grupperna g_ledare och g_personal, och användarna alice och bob. Linux är
VM 321 och Windows är VM 322. Alla resultat kommer från testskripten i
`skript/linux` och `skript/windows`.

## 1. Tre klasser eller en lista med rader

Linux har tre klasser: ägare, grupp och övriga. Var och en får r, w och x.
En mapp kan därför bara ha en grupp. Windows har en lista med rader (ACL),
och varje rad ger en grupp eller användare sina rättigheter. Listan kan ha
hur många rader som helst.

Gemensamt i Linux och Windows:

```text
drwxrws---+ 2 root g_personal 4096 Sep 30 00:21 /srv/Projekt/Gemensamt

# file: /srv/Projekt/Gemensamt
# owner: root
# group: g_personal
# flags: -s-
user::rwx
group::rwx
group:g_ledare:rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:g_ledare:rwx
default:mask::rwx
default:other::---

C:\Projekt\Gemensamt ISCX26-VG-WIN\g_personal:(OI)(CI)(M)
                     ISCX26-VG-WIN\g_ledare:(OI)(CI)(M)
```

På Linux kan en mapp bara ha en grupp i grundmodellen. Gemensamt tillhör
g_personal, och alice är bara med i g_ledare. Utan något mer hade hon
räknats som övriga och inte fått någon åtkomst. Därför fick g_ledare en egen
rad med en ACL (`setfacl`), som är ett tillägg till grundmodellen. `+` i
slutet av `drwxrws---+` visar att mappen har en ACL, och `getfacl` visar
raderna.

På Windows är listan med rader (ACL) grundmodellen. Både g_personal och
g_ledare har en egen rad, så alice får åtkomst via g_ledare utan något
tillägg.

Ett alternativ på Linux hade varit att lägga alice även i g_personal. Men
då får hon åtkomst överallt där den gruppen har rättigheter, inte bara i
Gemensamt, och en ny chef som bara läggs i g_ledare hade inte kommit in.
Uppgiften kräver att gruppen g_ledare har rättigheterna, inte bara alice.

M står för Modify. Det betyder att man får läsa, skriva, köra och ta bort
filer, men inte ändra rättigheter. (OI)(CI) betyder att rättigheten ärvs av
filer och undermappar.

På Linux motsvarar det ungefär gruppens rws på mappen. r låter en se
innehållet, w skapa och ta bort filer och x gå in i mappen. Två saker
skiljer:

- På Linux kan bara ägaren och root ändra rättigheter. Det finns ingen bit
  för det.
- s visar två saker: att gruppen har x och att setgid är satt. setgid är
  ingen rättighet. Den gör att nya filer får mappens grupp, vilket Windows
  löser med arv.

## 2. Arv

En ny fil som alice skapade i Gemensamt:

```text
-rw-rw----+ 1 alice g_personal 0 Sep 30 01:34 /srv/Projekt/Gemensamt/b10-ny.txt
# file: /srv/Projekt/Gemensamt/b10-ny.txt
# owner: alice
# group: g_personal
user::rw-
group::rwx	#effective:rw-
group:g_ledare:rwx	#effective:rw-
mask::rw-
other::---

C:\Projekt\Gemensamt\b10-ny.txt ISCX26-VG-WIN\g_personal:(I)(M)
                                ISCX26-VG-WIN\g_ledare:(I)(M)
                                BUILTIN\Administrators:(I)(F)
                                NT AUTHORITY\SYSTEM:(I)(F)
```

Arvet i Windows gick också åt andra hållet. En ny mapp på `C:\` ärvde att
alla användare (Users) fick läsa och skapa filer. Därför bröts arvet på
Projekt med `icacls /inheritance:r`, och rättigheterna sattes uttryckligen.

I Linux ärver en ny fil inte mappens rättigheter i grundmodellen. Två saker
avgör i stället vad den får:

- setgid bestämmer vilken grupp filen får. Utan setgid hade filen fått
  alices egen grupp alice. bob hade då räknats som övriga.
- Standard-ACL:en på Gemensamt (raderna som börjar med `default:`)
  bestämmer rättigheterna. Raderna kopieras till nya filer, så både
  g_personal och g_ledare får läsa och skriva, och övriga får ingenting.
  Utan standard-ACL hade umask bestämt, och g_ledare hade inte fått någon
  rad alls på nya filer.

I Windows ärver den nya filen hela mappens lista, både vem och vad på en
gång. Det syns på (I) i utdata. Därför räcker en mekanism. Standard-ACL:en
i Linux är närmast det Windows gör hela tiden.

Om arvet från `C:\` inte hade brutits hade Ledning ärvt raderna därifrån
utöver sina egna. Users, där bob ingår, hade fått läsrätt och dessutom rätt
att skapa filer och mappar. bob hade kunnat öppna och läsa filerna i
Ledning, och mappen hade inte längre varit skyddad. Genom att bryta arvet
med /inheritance:r finns bara de rader jag själv satt, och bob får ingen
åtkomst eftersom det saknas en rad för honom.

Det är ungefär samma sak som om mappen på Linux hade haft r-x för övriga i
stället för ---.

## 3. Den som inte nämns

I Linux får den som varken är ägare eller med i gruppen rättigheterna för
övriga. I Ledning är det 0, alltså ingenting. I Windows får den som inte
finns på någon rad ingenting alls, utan att det behöver stå. bob nekades i
Ledning i båda systemen:

```text
ls: cannot open directory '/srv/Projekt/Ledning': Permission denied

Get-ChildItem : Access to the path 'C:\Projekt\Ledning' is denied.
```

Linux är lättast att läsa. En rad med `ls -l` visar ägare, grupp och övriga,
och det finns inget mer att ta hänsyn till, så länge man inte använder ACL.
Nackdelen är att modellen är så enkel att två grupper på samma mapp kräver
ett tillägg. Då räcker inte `ls -l` längre, utan man måste läsa `getfacl`,
och det enda tecknet på att något mer finns är ett `+`. Man måste också
komma ihåg både setgid och standard-ACL. Glömmer man någon av dem blir det
fel på nya filer.

Windows ger mer kontroll, eftersom varje grupp kan få exakt de rättigheter den
behöver. Men listan blir snabbt lång, och rader kan komma via arv utan att man
själv har satt dem. Det var just det som hände med `C:\`: en ny mapp gav alla
användare läsrätt utan att någon hade bett om det. I Windows är det därför
lättare att av misstag ge för mycket åtkomst. I Linux är det lättare att ge
för lite.

## Slutsats

Linux och Windows löser samma problem på olika sätt. Linux har en enkel modell
med tre klasser och ingen arvsmekanism för rättigheter. För två grupper på
samma mapp och rättigheter på nya filer krävs tillägg: ACL, standard-ACL och
setgid. Windows har en lista med rader som ärvs
automatiskt, vilket gör det lätt att ge flera grupper åtkomst till samma mapp.
Samtidigt kan det ge rättigheter man inte räknat med.

Systemen nekar också på olika sätt. Windows nekar alla som saknar en rad, utan
att man behöver göra något. Linux ger övriga det som står i de tre sista
tecknen, och bob nekades i Ledning för att jag satte --- där. I labben ledde
båda till samma resultat: bob kom inte in i Ledning, och alice och bob kunde
arbeta tillsammans i Gemensamt.

## Källor

- [`man 1 chmod`](https://man7.org/linux/man-pages/man1/chmod.1.html): rättigheterna r, w och x för ägare, grupp och övriga
- [`man 2 chmod`](https://man7.org/linux/man-pages/man2/chmod.2.html): bara ägaren eller en privilegierad process (root) får ändra rättigheterna
- [`man 7 inode`](https://man7.org/linux/man-pages/man7/inode.7.html): setgid på en katalog ger nya filer katalogens grupp
- [`man 5 acl`](https://man7.org/linux/man-pages/man5/acl.5.html): ACL-rader, mask och hur standard-ACL ärvs av nya filer
- [`man 1 setfacl`](https://man7.org/linux/man-pages/man1/setfacl.1.html)
- [Microsoft Learn: icacls](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/icacls)
- [Microsoft Learn: ACE Inheritance](https://learn.microsoft.com/en-us/windows/win32/secauthz/ace-inheritance)
