# PRINTER SWITCH

Utilitario para Windows que permite **pausar e retomar impressoras instaladas**, independentemente do fabricante, por um atalho de teclado ou pelo icone na bandeja do sistema.

## Requisitos

- Windows com Windows PowerShell 5.1 e modulo `PrintManagement` disponivel.
- Uma impressora instalada e permissao de administrador para controlar a fila de impressao.

## Como utilizar

1. Extraia os arquivos para a mesma pasta.
2. Clique duas vezes em `INICIAR_PRINTER.bat`.
3. Autorize a elevacao de privilegios do Windows, se solicitada.
4. Use **Ctrl + Alt + P** para alternar entre impressora pausada e liberada.
5. Use o icone na bandeja do Windows para escolher a impressora, consultar a fila ou sair.

**Indicador:** verde = liberada; vermelho = bloqueada.

## Comportamento importante

- A primeira execucao registra a impressora selecionada como **OFF (pausada)**. O aplicativo aplica o estado ao iniciar.
- Ao mudar de **OFF para ON**, o programa **apaga todos os trabalhos da fila da impressora selecionada** antes de retomar a impressao. Essa exclusao e intencional no codigo original e pode causar perda de trabalhos pendentes.
- Para mudar de **ON para OFF**, apenas pausa a impressora, sem apagar a fila.
- As preferencias ficam em `%APPDATA%\PrinterSwitch\config.json`.
- O utilitario executa em segundo plano, com interface de bandeja e janela oculta.

## Arquivos

- `PRINTER_SWITCH.ps1` - implementacao em PowerShell e Windows Forms.
- `INICIAR_PRINTER.bat` - inicializador.

## Observacoes

Este pacote foi rebatizado a partir da versao 4.1, preservando a logica operacional. As preferencias da versao anterior **nao sao migradas automaticamente** para a nova pasta, por isso a selecao/estado salvo anteriormente nao aparecera na nova versao.

Os scripts foram revisados estaticamente, mas **nao foram testados em um computador Windows com impressoras reais**.
