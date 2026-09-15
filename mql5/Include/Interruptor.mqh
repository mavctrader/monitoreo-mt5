//+------------------------------------------------------------------+
//|                                                Interruptor.mqh   |
//|  Se escribe una sola vez. Cada bot propio lo incluye para        |
//|  obedecer parar/arrancar desde el panel.                         |
//|                                                                    |
//|  Uso, dentro del bot:                                             |
//|                                                                    |
//|    #include <Interruptor.mqh>                                     |
//|                                                                    |
//|    int OnInit()                                                   |
//|      {                                                             |
//|       Interruptor_Iniciar();                                       |
//|       ... resto del OnInit del bot ...                             |
//|      }                                                             |
//|                                                                    |
//|    void OnTick()                                                   |
//|      {                                                             |
//|       if(!Interruptor_Permitido())                                 |
//|          return; // parado: no abre nada nuevo. Lo abierto sigue.  |
//|       ... lógica normal del bot ...                                |
//|      }                                                             |
//|                                                                    |
//|  Copiar este archivo a <carpeta de datos>\MQL5\Include\ antes de   |
//|  compilar los bots.                                                |
//+------------------------------------------------------------------+
#property strict

#define INTERRUPTOR_CARPETA "MonitoreoMT5\\"
#define INTERRUPTOR_INTERVALO 5 // segundos entre lecturas del interruptor

bool     g_interruptor_permitido = true;
datetime g_interruptor_ultima_lectura = 0;

string InterruptorArchivoEstado()
  {
   return INTERRUPTOR_CARPETA + "interruptor_"
      + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_"
      + IntegerToString(ChartID()) + ".json";
  }

string InterruptorArchivoConfirmacion()
  {
   return INTERRUPTOR_CARPETA + "bot_estado_"
      + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_"
      + IntegerToString(ChartID()) + ".json";
  }

// El agente solo escribe "parado" o "arrancado" en este archivo (nunca
// JSON arbitrario), así que alcanza con buscar la palabra en vez de
// escribir un parser JSON completo en MQL5.
void InterruptorLeer()
  {
   string archivo = InterruptorArchivoEstado();
   if(!FileIsExist(archivo, FILE_COMMON))
     {
      g_interruptor_permitido = true; // sin orden todavía = arrancado
      return;
     }

   int handle = FileOpen(archivo, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   string contenido = "";
   while(!FileIsEnding(handle))
      contenido += FileReadString(handle);
   FileClose(handle);

   g_interruptor_permitido = (StringFind(contenido, "parado") < 0);
  }

void InterruptorEscribirConfirmacion()
  {
   string queHace = g_interruptor_permitido ? "arrancado" : "parado";
   string json = "{\"confirmado\":\"" + queHace + "\"}";

   int handle = FileOpen(InterruptorArchivoConfirmacion(), FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return;
   uchar bytes[];
   int n = StringToCharArray(json, bytes, 0, WHOLE_ARRAY, CP_UTF8);
   if(n > 1)
      FileWriteArray(handle, bytes, 0, n - 1);
   FileClose(handle);
  }

// Llamar una vez en OnInit.
void Interruptor_Iniciar()
  {
   InterruptorLeer();
   InterruptorEscribirConfirmacion();
   g_interruptor_ultima_lectura = TimeCurrent();
  }

// Llamar en cada OnTick. Internamente solo relee el archivo cada
// INTERRUPTOR_INTERVALO segundos, así que llamarla seguido no cuesta nada.
bool Interruptor_Permitido()
  {
   if(TimeCurrent() - g_interruptor_ultima_lectura >= INTERRUPTOR_INTERVALO)
     {
      bool antes = g_interruptor_permitido;
      InterruptorLeer();
      if(g_interruptor_permitido != antes)
         InterruptorEscribirConfirmacion();
      g_interruptor_ultima_lectura = TimeCurrent();
     }
   return g_interruptor_permitido;
  }
