# Programmentwurf TIT20 "timediff"

Dies ist der Programmentwurf von:
- David Felder
- Florian Herkommer
- Florian Glaser

## Kompilierung

Zum Erstellen der Programme folgenden Code ausführen:

```bash
# tar.gz entpacken
mkdir snp
tar -xzvf pe_tit20_felder_herkommer_glaser.tar.gz -C ./snp

# Bauen der Programme
cd snp/pe2022
make
```

## Ausführen

```bash
# Ausführen der Tests
./list_test

# Erstellen von 10.000 timestamps ab dem 01.01.1970 mit einem timediff von 0 bis 1.000.000 Sekunden (floating point numbers)
python3 timestamps_gen.py > timestamps

# Ausführen von timediff (dauert mit 10.000 timestamps ca. 2min)
./timediff < timestamps
```

## Q&A

### Wie kann ich timestamps einlesen?

- Das Einlesen der timestamps ist nur über eine Datei möglich.
- In der Datei dürfen keine leeren Zeilen vorkommen.

Beispiel:
```bash
# Funktioniert
0.0
379231.60528977285
666521.8264759808
897478.9541289626
1148705.3620912628
1862678.250194165

# Fehler
0.0
379231.60528977285
666521.8264759808

897478.9541289626
1148705.3620912628
```

### Wie müssen die eingelesen timestamps aussehen?

Sekundenanteil:
- Mindestens 1- bis maximal 10-stellig
- Besteht nur aus den Ziffern 0-9

Trennzeichen muss ein Punkt sein.

Mikrosekundenanteil:
- Mindestens 1-stellig
- Besteht nur aus den Ziffern 0-9
- Ab der 6ten Stelle werden alle folgende Ziffern abgeschnitten

### Welcher Algorithmus wird für das Suchen in der Funktion "list_find" verwendet?
[Binäre Suche](https://de.wikipedia.org/wiki/Bin%C3%A4re_Suche)

### Gibt es sonstige Besonderheiten?
- Es können maximal 10.000 timestamps eingelesen werden.
- Es müssen mindestens 2 timestmaps eingelesen werden.
- Die Liste der timestamps muss aufsteigend sortiert sein.
- Die Maximallänge der gesamten Eingabe darf 180.000 Byte nicht überschreiten.
  - Es passen 10.000 valide timestamps in diese Größe.
  - Der Speicher ist jedoch zu klein für 10.000 timestamps mit mehr als 6 Nachkommastellen.

## Aufteilung der Arbeit
Das komplette Team hat immer gemeinsam an dem Projekt gearbeitet. Daher kann keine Aufteilung von bestimmten Funktionen zu bestimmten Personen erfolgen.
