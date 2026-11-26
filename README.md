# La Bibbia del Game Design

Lezioni di Game Design (analogico e digitale), con elementi di Unreal Engine e interventi a conferenze e seminari, riscritte in LaTeX in forma di libro.

## Struttura

| Percorso | Contenuto |
|---|---|
| `main.tex` | File principale: preambolo, frontespizio, indice e `\input` di tutti i capitoli, divisi in parti |
| `Seminari/` | Parte 0 – Seminari per il Game Designer (`GD0_*`) |
| `Conferenze/` | Conferenze: GAMM di Roma, Checkpoint Festival (`CONF1_*`, capitoli C1.x) e On The Road a Zagarolo, giorno 1 (`CONF2_*`, C2.x) e giorno 2 (`CONF3_*`, C3.x); i file `*_0_*` introducono la parte e ciascun evento |
| `UE/` | Parte 1 – Fondamenti di Unreal Engine (`UE1`–`UE16`) |
| `AGD/` | Parte 2 – Analog Game Design (`AGD1`–`AGD16`) |
| `Professioni/` | Parte 3 – Alcune professioni nel mondo videoludico (`AIV*`) |
| `GD1/` | Parte 4 – Game Design (`GD1`–`GD17`) |
| `REV/GD/` | Parte 5 – Revisioni dei compiti |
| `blueprint_ninja/` | Documento a parte: *Diventare ninja dei Blueprint* (ha il suo `main.tex` e lo stile `bpninja.sty`) |
| `blueprint_livelli/` | *Rifare i livelli in Blueprint* (solo PDF, nessun sorgente) |
| `appunti/` | Appunti di lavoro non ancora integrati nel libro |

Ogni capitolo è un file `.tex` senza preambolo, pensato per essere incluso da `main.tex`. I pacchetti necessari sono caricati in `main.tex`.

> Nota: in `main.tex` la parte di Unreal Engine include per ora solo `UE1` e `UE2`; i capitoli `UE3`–`UE16` sono nel repository e si attivano aggiungendo le relative righe `\input{UE/...}`.

## Compilare

Serve una distribuzione TeX completa (TeX Live o MiKTeX) con TikZ. Dalla radice del repository:

```bash
latexmk -pdf main.tex
# oppure, a mano (due passaggi per indice e riferimenti)
pdflatex main.tex && pdflatex main.tex
```

La guida ai Blueprint si compila dalla sua cartella:

```bash
cd blueprint_ninja && latexmk -pdf main.tex
```

I file di compilazione (`.aux`, `.log`, `.toc`, …) e i PDF generati sono esclusi da `.gitignore`.

## Cosa non è nel repository

I libri di riferimento e i regolamenti di terzi (protetti da copyright), i compiti dei compagni di corso e i PDF di anteprima restano fuori dal repository.

## Licenza

Vedi [`LICENSE`](./LICENSE).
