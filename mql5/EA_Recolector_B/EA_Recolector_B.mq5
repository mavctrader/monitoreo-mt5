//+------------------------------------------------------------------+
//|                                            EA_Recolector_B.mq5   |
//|  Lee el estado de la cuenta y lo escribe en la carpeta Common.   |
//|  No opera. No sale a internet. No guarda credenciales.           |
//|  Un gráfico por terminal.                                        |
//|                                                                  |
//|  VERSIÓN B - ABIERTA EL 19/09/2026, arranca donde quedó la A.    |
//|  Es la versión viva: todo cambio y toda mejora va acá. Nunca se  |
//|  copia ni se vuelca sobre la A, que quedó cerrada.               |
//|                                                                  |
//|  A y B corren a la vez en la VPS, en cuentas distintas: la A en  |
//|  las que operan cross. Cada archivo que se escribe lleva el      |
//|  número de cuenta en el nombre, así que no se pisan. Lo único    |
//|  prohibido es poner A y B sobre la MISMA cuenta.                 |
//|                                                                  |
//|  OJO: el Agente lee lo que escriben las dos. Si acá se cambia el |
//|  formato de un archivo, tiene que seguir entendiendo también lo  |
//|  que escribe la A, o las cuentas cross dejan de reportar.        |
//+------------------------------------------------------------------+
#property copyright "Centro de Monitoreo MT5"
#property version   "1.10"
#property strict

input int IntervaloSegundos = 5; // cada cuánto escribe y revisa órdenes de descarga

#define CARPETA "MonitoreoMT5\\"

// Letra de esta versión. Viaja en el estado para que el Agente sepa con qué
// versión está hablando en cada cuenta. La A no la escribe: se cerró antes de
// que existiera el campo, y el Agente la reconoce por eso mismo.
#define VERSION "B"

//+------------------------------------------------------------------+
//| Utilidades                                                       |
//+------------------------------------------------------------------+
string JsonEscape(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\n", " ");
   StringReplace(s, "\r", " ");
   return s;
  }

string IsoTime(datetime t)
  {
   string s = TimeToString(t, TIME_DATE | TIME_SECONDS);
   StringReplace(s, ".", "-");
   StringReplace(s, " ", "T");
   return s + "Z";
  }

string LoginStr()
  {
   return IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN));
  }

// Escribe contenido UTF-8, sobrescribiendo el archivo.
void EscribirTexto(string archivo, string contenido)
  {
   int handle = FileOpen(archivo, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
     {
      Print("No se pudo escribir ", archivo, " error ", GetLastError());
      return;
     }
   uchar bytes[];
   int n = StringToCharArray(contenido, bytes, 0, WHOLE_ARRAY, CP_UTF8);
   if(n > 1)
      FileWriteArray(handle, bytes, 0, n - 1); // sin el terminador nulo
   FileClose(handle);
  }

// Agrega una línea UTF-8 al final del archivo (lo crea si no existe).
void AgregarLinea(string archivo, string linea)
  {
   int handle = FileOpen(archivo, FILE_READ | FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
     {
      Print("No se pudo abrir ", archivo, " error ", GetLastError());
      return;
     }
   FileSeek(handle, 0, SEEK_END);
   uchar bytes[];
   int n = StringToCharArray(linea + "\n", bytes, 0, WHOLE_ARRAY, CP_UTF8);
   if(n > 1)
      FileWriteArray(handle, bytes, 0, n - 1);
   FileClose(handle);
  }

//+------------------------------------------------------------------+
//| Estado de la cuenta                                              |
//+------------------------------------------------------------------+
void EscribirEstado()
  {
   string json = "{"
      + "\"cuenta_id\":" + LoginStr() + ","
      + "\"version\":\"" + VERSION + "\","
      + "\"broker\":\"" + JsonEscape(AccountInfoString(ACCOUNT_COMPANY)) + "\","
      + "\"saldo\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ","
      + "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ","
      + "\"flotante\":" + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + ","
      + "\"margen_libre\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + ","
      + "\"algo_trading\":" + (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "true" : "false") + ","
      + "\"visto_en\":\"" + IsoTime(TimeGMT()) + "\""
      + "}";
   EscribirTexto(CARPETA + "estado_" + LoginStr() + ".json", json);
  }

//+------------------------------------------------------------------+
//| Posiciones abiertas                                              |
//+------------------------------------------------------------------+
void EscribirPosiciones()
  {
   string items = "";
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(items != "")
         items += ",";
      string tipo = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "compra" : "venta";
      items += "{"
         + "\"ticket\":" + IntegerToString((long)ticket) + ","
         + "\"simbolo\":\"" + JsonEscape(PositionGetString(POSITION_SYMBOL)) + "\","
         + "\"tipo\":\"" + tipo + "\","
         + "\"volumen\":" + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + ","
         + "\"apertura\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 5) + ","
         + "\"sl\":" + DoubleToString(PositionGetDouble(POSITION_SL), 5) + ","
         + "\"tp\":" + DoubleToString(PositionGetDouble(POSITION_TP), 5) + ","
         + "\"beneficio\":" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2) + ","
         + "\"abierta_en\":\"" + IsoTime((datetime)PositionGetInteger(POSITION_TIME)) + "\""
         + "}";
     }
   string json = "{\"cuenta_id\":" + LoginStr() + ",\"posiciones\":[" + items + "]}";
   EscribirTexto(CARPETA + "posiciones_" + LoginStr() + ".json", json);
  }

//+------------------------------------------------------------------+
//| Costo del spread de cada posición                                |
//|                                                                    |
//| MT5 no informa el spread como un dato de la operación: va metido   |
//| en el precio de entrada. Se mide al ver la posición por primera    |
//| vez, calculando lo que cuesta cruzar la horquilla con ese volumen. |
//| Solo se mide una vez por ticket; después el precio ya se movió.    |
//+------------------------------------------------------------------+
ulong g_spreads_medidos[];

bool SpreadYaMedido(ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_spreads_medidos); i++)
      if(g_spreads_medidos[i] == ticket)
         return true;
   return false;
  }

void MedirSpreadsNuevos()
  {
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || SpreadYaMedido(ticket))
         continue;

      string simbolo = PositionGetString(POSITION_SYMBOL);
      double volumen = PositionGetDouble(POSITION_VOLUME);
      double horquilla = SymbolInfoDouble(simbolo, SYMBOL_ASK) - SymbolInfoDouble(simbolo, SYMBOL_BID);
      double tamTick = SymbolInfoDouble(simbolo, SYMBOL_TRADE_TICK_SIZE);
      double valorTick = SymbolInfoDouble(simbolo, SYMBOL_TRADE_TICK_VALUE);

      double costo = 0;
      if(tamTick > 0)
         costo = horquilla / tamTick * valorTick * volumen;

      string json = "{"
         + "\"cuenta_id\":" + LoginStr() + ","
         + "\"ticket\":" + IntegerToString((long)ticket) + ","
         + "\"simbolo\":\"" + JsonEscape(simbolo) + "\","
         + "\"volumen\":" + DoubleToString(volumen, 2) + ","
         + "\"costo\":" + DoubleToString(costo, 2) + ","
         + "\"medido_en\":\"" + IsoTime(TimeGMT()) + "\""
         + "}";
      AgregarLinea(CARPETA + "spreads_" + LoginStr() + ".jsonl", json);

      int n = ArraySize(g_spreads_medidos);
      ArrayResize(g_spreads_medidos, n + 1);
      g_spreads_medidos[n] = ticket;
     }
  }

//+------------------------------------------------------------------+
//| Depósitos y retiros                                              |
//+------------------------------------------------------------------+
void PublicarMovimiento(ulong ticket, datetime cuando)
  {
   string json = "{"
      + "\"cuenta_id\":" + LoginStr() + ","
      + "\"ticket\":" + IntegerToString((long)ticket) + ","
      + "\"monto\":" + DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT), 2) + ","
      + "\"comentario\":\"" + JsonEscape(HistoryDealGetString(ticket, DEAL_COMMENT)) + "\","
      + "\"ocurrido_en\":\"" + IsoTime(cuando) + "\""
      + "}";
   AgregarLinea(CARPETA + "movimientos_" + LoginStr() + ".jsonl", json);
  }

// Al arrancar recorre TODO el historial una vez y publica los movimientos de
// saldo, incluido el depósito inicial. El recorrido normal solo mira lo nuevo,
// y esos movimientos suelen ser más viejos que el marcador. Repetirlos no
// molesta: el agente los guarda por número de ticket, sin duplicar.
void EscribirMovimientosHistoricos()
  {
   if(!HistorySelect(0, TimeCurrent() + 1))
      return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if((ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE) != DEAL_TYPE_BALANCE)
         continue;
      PublicarMovimiento(ticket, (datetime)HistoryDealGetInteger(ticket, DEAL_TIME));
     }
  }

//+------------------------------------------------------------------+
//| Operaciones cerradas: solo lo nuevo desde el último envío        |
//+------------------------------------------------------------------+
void EscribirOperacionesNuevas()
  {
   string nombreCursor = "MonitoreoMT5_UltimoCierre_" + LoginStr();
   datetime desde = 0;
   if(GlobalVariableCheck(nombreCursor))
      desde = (datetime)GlobalVariableGet(nombreCursor);

   if(!HistorySelect(desde, TimeCurrent() + 1))
      return;

   datetime maxCierre = desde;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      datetime cierre = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(cierre <= desde)
         continue;

      ENUM_DEAL_TYPE tipoDeal = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);

      // Depósitos y retiros: mueven el saldo sin que haya operación.
      if(tipoDeal == DEAL_TYPE_BALANCE)
        {
         PublicarMovimiento(ticket, cierre);
         if(cierre > maxCierre)
            maxCierre = cierre;
         continue;
        }

      // Solo cierres de posiciones.
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;
      if(tipoDeal != DEAL_TYPE_BUY && tipoDeal != DEAL_TYPE_SELL)
         continue;

      string tipo = (tipoDeal == DEAL_TYPE_BUY) ? "venta" : "compra"; // el deal de cierre es el tipo contrario a la apertura
      double volumen = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double salida = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double beneficio = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double comision = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      long posicionId = (long)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      string simbolo = HistoryDealGetString(ticket, DEAL_SYMBOL);

      // Precio y hora de apertura: primer deal de la misma posición (DEAL_ENTRY_IN).
      double entrada = 0;
      datetime abierta = 0;
      // De paso se junta la comisión de apertura: MT5 la cobra en las dos
      // puntas y el deal de cierre solo trae la suya, así que sin esto la
      // comisión quedaba a la mitad.
      double comisionEntrada = 0;
      double volumenEntrada = 0;
      if(HistorySelectByPosition(posicionId))
        {
         int nDeals = HistoryDealsTotal();
         for(int j = 0; j < nDeals; j++)
           {
            ulong t2 = HistoryDealGetTicket(j);
            if(t2 == 0)
               continue;
            if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t2, DEAL_ENTRY) != DEAL_ENTRY_IN)
               continue;
            if(entrada == 0)
              {
               entrada = HistoryDealGetDouble(t2, DEAL_PRICE);
               abierta = (datetime)HistoryDealGetInteger(t2, DEAL_TIME);
              }
            comisionEntrada += HistoryDealGetDouble(t2, DEAL_COMMISSION);
            volumenEntrada += HistoryDealGetDouble(t2, DEAL_VOLUME);
           }
        }
      HistorySelect(desde, TimeCurrent() + 1); // restaurar el conjunto de deals tras la consulta por posición

      // La comisión de apertura se reparte según el volumen que cierra este
      // deal: si la posición se cierra en partes, cada parte se lleva la
      // porción que le toca y no la comisión entera.
      if(volumenEntrada > 0)
         comision += comisionEntrada * (volumen / volumenEntrada);
      else
         comision += comisionEntrada;

      string json = "{"
         + "\"cuenta_id\":" + LoginStr() + ","
         + "\"ticket\":" + IntegerToString((long)ticket) + ","
         + "\"simbolo\":\"" + JsonEscape(simbolo) + "\","
         + "\"tipo\":\"" + tipo + "\","
         + "\"volumen\":" + DoubleToString(volumen, 2) + ","
         + "\"entrada\":" + DoubleToString(entrada, 5) + ","
         + "\"salida\":" + DoubleToString(salida, 5) + ","
         + "\"beneficio\":" + DoubleToString(beneficio, 2) + ","
         + "\"comision\":" + DoubleToString(comision, 2) + ","
         + "\"swap\":" + DoubleToString(swap, 2) + ","
         + "\"abierta_en\":\"" + IsoTime(abierta) + "\","
         + "\"cerrada_en\":\"" + IsoTime(cierre) + "\""
         + "}";
      AgregarLinea(CARPETA + "operaciones_" + LoginStr() + ".jsonl", json);

      if(cierre > maxCierre)
         maxCierre = cierre;
     }

   if(maxCierre > desde)
      GlobalVariableSet(nombreCursor, (double)maxCierre);
  }

//+------------------------------------------------------------------+
//| Qué EA hay en un gráfico y a qué canal de copia apunta.          |
//|                                                                    |
//| MQL5 no deja consultar eso directamente, así que se guarda la      |
//| plantilla del gráfico (que incluye el EA y sus parámetros), se     |
//| leen SOLO el nombre del EA y el archivo master.jsonN, y se borra.  |
//| El resto de los parámetros no se lee ni se guarda: ahí van cosas   |
//| como la contraseña del copiador.                                   |
//+------------------------------------------------------------------+
// Deja la plantilla de cada gráfico en disco para que el Agente pueda ver
// qué EA hay puesto y con qué parámetros. El EA no la puede leer él mismo:
// MT5 la guarda en MQL5\Profiles\Templates\ y desde MQL5 solo se puede leer
// MQL5\Files\. El Agente (Python) sí llega, la lee y la borra.
void GuardarPlantilla(long chartId)
  {
   ChartSaveTemplate(chartId, "MonitoreoMT5_tpl_" + IntegerToString(chartId));
  }

//+------------------------------------------------------------------+
//| Inventario de gráficos abiertos (qué bots hay cargados)          |
//|                                                                    |
//| Guardar la plantilla es una operación de disco, así que se hace    |
//| una vez por minuto y no en cada pasada.                            |
//+------------------------------------------------------------------+
#define INTERVALO_PLANTILLAS 60 // segundos

datetime g_plantillas_en = 0;

void EscribirGraficos()
  {
   // TimeLocal y no TimeCurrent: con el mercado cerrado la hora del servidor
   // no avanza y las plantillas dejarían de refrescarse.
   bool guardarPlantillas = (TimeLocal() - g_plantillas_en >= INTERVALO_PLANTILLAS);

   string items = "";
   long chartId = ChartFirst();
   while(chartId >= 0)
     {
      if(guardarPlantillas)
         GuardarPlantilla(chartId);

      if(items != "")
         items += ",";
      items += "{"
         + "\"grafico_id\":" + IntegerToString(chartId) + ","
         + "\"simbolo\":\"" + JsonEscape(ChartSymbol(chartId)) + "\","
         + "\"periodo\":\"" + EnumToString((ENUM_TIMEFRAMES)ChartPeriod(chartId)) + "\""
         + "}";
      chartId = ChartNext(chartId);
     }

   if(guardarPlantillas)
      g_plantillas_en = TimeLocal();

   string json = "{\"cuenta_id\":" + LoginStr() + ",\"graficos\":[" + items + "]}";
   EscribirTexto(CARPETA + "graficos_" + LoginStr() + ".json", json);
  }

//+------------------------------------------------------------------+
//| Último recurso: cerrar el gráfico de un bot que no responda.     |
//| El Agente escribe una línea "id|grafico_id" por orden pendiente  |
//| en ordenes_pendientes_<login>.txt. Acá se confirma en            |
//| ordenes_hechas_<login>.txt qué ids ya se ejecutaron.             |
//+------------------------------------------------------------------+
void ProcesarOrdenesDescargar()
  {
   string archivo = CARPETA + "ordenes_pendientes_" + LoginStr() + ".txt";
   if(!FileIsExist(archivo, FILE_COMMON))
      return;

   int handle = FileOpen(archivo, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   while(!FileIsEnding(handle))
     {
      string linea = FileReadString(handle);
      if(StringLen(linea) == 0)
         continue;

      string partes[];
      int n = StringSplit(linea, '|', partes);
      if(n < 2)
         continue;

      string id = partes[0];
      long graficoId = (long)StringToInteger(partes[1]);
      if(ChartClose(graficoId))
         AgregarLinea(CARPETA + "ordenes_hechas_" + LoginStr() + ".txt", id);
     }
   FileClose(handle);
  }

//+------------------------------------------------------------------+
//| Ciclo principal                                                  |
//+------------------------------------------------------------------+
void CicloCompleto()
  {
   EscribirEstado();
   MedirSpreadsNuevos();
   EscribirPosiciones();
   EscribirOperacionesNuevas();
   EscribirGraficos();
   ProcesarOrdenesDescargar();
  }

int OnInit()
  {
   if(!FolderCreate(CARPETA, FILE_COMMON))
      Print("Aviso: no se pudo crear/confirmar la carpeta ", CARPETA, " error ", GetLastError());

   EscribirMovimientosHistoricos();
   CicloCompleto();
   EventSetTimer(IntervaloSegundos);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

void OnTimer()
  {
   CicloCompleto();
  }
