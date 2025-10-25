# Pipeline de Ingesta y Transformación de Datos en Azure para Ventas de Retail


## Descripción

Este proyecto demuestra un pipeline completo de ingeniería de datos en Microsoft Azure. 
Automatiza la ingesta, transformación y almacenamiento de datos de ventas de retail usando 
Azure Blob Storage, ADLS Gen2, Azure Data Factory y Synapse Analytics. 
Los datasets finales se estructuran en capas Bronze, Silver y Gold.


## Tabla de Contenidos

- [Arquitectura](#arquitectura)
- [Tecnologías](#tecnologías)
- [Estructura del Proyecto](#estructura-del-proyecto)
- [Guía de Configuración](#guía-de-configuración)
- [Uso del Proyecto](#uso-del-proyecto)
- [Contribuciones](#contribuciones)
- [Licencia](#licencia)


## Arquitectura

El pipeline sigue una arquitectura tipo Lakehouse y se ejecuta de forma completamente automatizada:

1. **Ingesta programada con Azure Data Factory (ADF)**:
   - El flujo está programado para correr diariamente en la madrugada.
   - Toma los archivos CSV de sales y customers generados por cada tienda en Azure Blob Storage.
   - Detecta automáticamente los archivos correspondientes al día y los copia hacia ADLS Gen2.

2. **Estructura del contenedor Blob Storage**:
 - A continuación se muestra la estructura del Blob Storage:
```
   blobstoresproject/
   │
   └── incoming/                      # Carpeta principal de entrada (fuente original de datos)
      ├── store-a/
      │   ├── sales_20251017.csv      # Archivo de ventas diario de la tienda A
      │   └── customers_20251017.csv  # Archivo de clientes diario de la tienda A
      │
      ├── store-b/
      │   ├── sales_20251017.csv      # Archivo de ventas diario de la tienda B
      │   └── customers_20251017.csv  # Archivo de clientes diario de la tienda B
      │
      ├── store-c/
      │   ├── sales_20251017.csv      # Archivo de ventas diario de la tienda C
      │   └── customers_20251017.csv  # Archivo de clientes diario de la tienda C
      │
      ├── suppliers/
      │   └── suppliers_20251017.csv  # Datos maestros de proveedores (actualización diaria)
      │
      └── products/
         └── products_20251017.csv    # Datos maestros de productos (actualización diaria)
```
3. **Estructura del contenedor ADLS Gen2**:
 - A continuación se muestra la estructura del contenedor ADLS Gen2:
 ```
   adlsstoresproject/
   │
   ├── landing/                    # Capa Raw: archivos originales copiados desde Blob Storage por ADF
   │   ├── store-a/
   │   │   ├── customers.csv       # Datos crudos de clientes (día actual)
   │   │   └── sales.csv           # Datos crudos de ventas (día actual)
   │   │
   │   ├── store-b/                # Archivos de la tienda B
   │   └── store-c/                # Archivos de la tienda C
   │
   ├── processed/                  # Lake Database con tablas Delta (capa Bronze)
   │   ├── customers/              # Datos crudos unificados en formato Delta
   │   ├── sales/                  # Ventas integradas en formato Delta
   │   ├── suppliers/              # Proveedores validados (no pasan a Silver)
   │   └── products/               # Productos validados (no pasan a Silver)
   │
   ├── silver/                     # Lake Database con tablas Delta (capa Silver)
   │   ├── customers/              # Datos validados y estandarizados de clientes
   │   └── sales/                  # Datos limpios y transformados de ventas
   │
   ├── temporal_files/             # Archivos Parquet intermedios generados por notebooks
   │                               # antes de ser convertidos a Delta en la capa Bronze
   │
   ├── gold/                       # (Opcional) Estructura referencial, no usada directamente
   │                               # ya que la capa Gold se almacena en SQL Database (Synapse)
   │
   └── synapse/                    # Carpeta creada automáticamente por Synapse Analytics
                                   # usada internamente para la integración con notebooks
```
4. **Capa Bronze**:  
   - Esta capa permite unificar la estructura de los datos sin perder los registros originales.   
   - Se crea un **Common Data Model (CDM)** (y se agregan campos: store_id, created_at, year, month, day, unique_id) para unificar todas las ventas y clientes de las N tiendas dentro de sus respectivos datasets en formato Parquet.  
   - Los datos unificados se ingieren en tablas Delta usando notebooks de PySpark. 
   - Posteriormente, se construye la capa Bronze con estos dos modelos (sales y customers) en un **Lake Database** con formato Delta, particionado por Año, Mes y Día, con el fin de optimizar consultas futuras.
   - Los datasets **sales** y **customers** se procesan de forma **incremental**, agregando únicamente los nuevos registros de cada día, lo que permite mantener el histórico sin reprocesar toda la tabla.  
   - En cambio, los datasets **suppliers** y **products** se cargan mediante un proceso de **carga completa (full load)**, ya que provienen de fuentes maestras estables y se reemplazan en cada ejecución.
   - Para manejar la ingesta incremental y poder identificar qué registros son procesados en la capa Silver, se agrega el campo "is_validated" a cada tabla incremental.

5. **Capa Silver**:  
   - En esta capa se realiza la limpieza, estandarización y validación de los datos provenientes de Bronze.  
   - Se corrigen tipos de datos, formatos de fechas, valores nulos y registros duplicados.  
   - Se generan llaves únicas para garantizar la integridad referencial.  
   - Se aplican **validaciones de calidad de datos** y se ejecutan merges basados en campos clave como `unique_id`.  
   - Los datos resultantes se guardan nuevamente en Delta Tables, listos para su uso analítico.

6. **Capa Gold**:  
   - En esta capa se preparan datasets agregados y enriquecidos para análisis y consumo en herramientas de BI.  
   - Se crean tablas con métricas resumidas, como ventas totales por tienda, por producto o por cliente.  
   - Los datos procesados se almacenan en una **base de datos SQL (SQL Database)** dentro de **Azure Synapse Analytics**, en lugar de un Lake Database.  
   - Esta decisión permite una mejor optimización de consultas, uso de índices y conectividad directa con herramientas de visualización como Power BI.  
   - Los datos se organizan por temas de negocio (ventas, clientes, desempeño de tiendas, etc.) y se exponen como una capa de presentación confiable para reportes y análisis avanzados.

7. **Orquestación y automatización**:  
   - Todo el flujo de datos está coordinado mediante **Azure Data Factory (ADF)**, que actúa como el orquestador central del proyecto.  
   - El diseño está basado en una arquitectura **modular y parametrizada**, compuesta por varios *pipelines* independientes que se comunican entre sí mediante el paso de parámetros dinámicos.  
   - El **pipeline principal (`pl_main`)** no maneja parámetros, pero controla la ejecución completa del proceso:  
     - Primero ejecuta el pipeline de ingesta (`pl_ingest_blob_to_landing`), encargado de copiar los archivos diarios desde **Blob Storage** hacia **ADLS Gen2**.  
     - Luego ejecuta tres *notebooks* de **Azure Synapse Analytics**, responsables de las transformaciones en las capas **Bronze**, **Silver** y **Gold** (`01_move_landing_to_processed`, `02_transform_silver`, `03_model_gold`).  
   - El **pipeline `pl_ingest_blob_to_landing`** identifica los archivos válidos del día en Blob Storage, filtrándolos por tienda y tipo de dataset (sales, customers, products, suppliers).  
     - Utiliza una variable interna (`currentStore`) para iterar dinámicamente sobre cada tienda.  
     - Por cada tienda o dataset, invoca el pipeline **`pl_get_blob_files`** y le envía parámetros dinámicos como:  
       - `storesFiles`: lista de archivos filtrados a procesar.  
       - `storeName`: nombre de la tienda o dataset (por ejemplo: `store-a`, `store-b`, `store-c`).  
   - El **pipeline `pl_get_blob_files`** recibe estos parámetros, itera sobre la lista de archivos y copia cada uno desde **Blob Storage** hacia su carpeta correspondiente en **ADLS Gen2** (`landing/{store}/`).  
     - Los parámetros se usan dentro de expresiones dinámicas para construir las rutas de origen y destino, lo que permite una ejecución completamente automatizada.  
   - Gracias a este diseño modular y parametrizado, el flujo puede **procesar múltiples tiendas de forma escalable**, reutilizando los mismos pipelines sin duplicar código ni configuraciones adicionales.


## Tecnologías

- **Microsoft Azure**
  - **Azure Blob Storage**: Almacenamiento de archivos de entrada (capa *incoming*).  
  - **Azure Data Lake Storage Gen2 (ADLS)**: Almacenamiento principal de datos en capas *landing* y *processed*.  
  - **Azure Data Factory (ADF)**: Orquestación de pipelines y ejecución de notebooks de Synapse.  
  - **Azure Synapse Analytics**: Procesamiento, transformación y modelado de datos.  
    - **Lake Database**: Estructuración de datos en capas *Bronze* y *Silver*.  
    - **SQL Database**: Modelado final y análisis en la capa *Gold*.

- **Python / PySpark**: Ingesta, validación y transformación de datos.  
- **Delta Lake**: Almacenamiento transaccional con versionamiento de datasets.  
- **SQL**: Creación de tablas, vistas y consultas analíticas.  
- **Git & GitHub**: Control de versiones y documentación del proyecto.


## Estructura del proyecto
```
📦 azure-data-project/
│
├── 📁 adf/
│   ├── pipeline_main.json                        # Pipeline principal orquestador en Azure Data Factory
│   ├── pipeline_sales.json                       # Pipeline para ingesta de ventas
│   └── pipeline_customers.json                   # Pipeline para ingesta de clientes
│
├── 📁 data/
│   ├── 📁 incoming/                              # Archivos originales (simulación del Blob Storage)
│   └── 📁 landing/                               # Datos copiados a la capa landing de un día en particular (ADLS)
│
├── 📁 docs/
│   ├── project architecture.png                  # Diagrama de arquitectura del proyecto
│   ├── adf_pipeline_get_blob_files.png           # Pipeline para identificar archivos en el Blob Storage
│   ├── adf_pipeline_ingest_blob_to_landing.png   # Pipeline para mover archivos desde Blos Storage hacia ADSL Gen2
│   └── adf_pipeline_main.png                     # Pipeline principal
│
├── 📁 notebooks/
│   ├── 01_move_landing_to_processed.ipynb        # Ingesta y creación de tablas Delta en Bronze
│   ├── 02_transform_silver.ipynb                 # Limpieza y estandarización en Silver
│   └── 03_model_gold.ipynb                       # Modelado final y carga en SQL Database
│
├── 📁 sql/
│   ├── number_of_sales_by_store_and_year.sql     # Cantidad de ventas por tienda por año
│   ├── top_15_best_selling_products.sql          # Top 15 de productos más vendidos
│   └── total_sales_by_store_and_year.sql         # Total dinero vendido por tienda por año
│
└── README-ES.md                                  # Documentación principal del proyecto
```

## Guía de configuración

Esta guía describe los pasos generales y configuraciones necesarias para implementar la solución en un entorno de **Microsoft Azure**.

1. **Crear los recursos base en Azure**  
   - **Resource Group:** `rgoup-stores`  
   - **Región:** East US 2  
   - **Servicios principales:**  
     - Azure Data Lake Storage Gen2 (`adlsstoresproject`)  
     - Azure Blob Storage (`blobstoresproject`)  
     - Azure Synapse Analytics (`synapse-stores`)
     - Azure SQL Database (`stores-sql-db-gold`)    
     - Azure Data Factory (`adf-storesproject`)  

2. **Estructurar los contenedores**  
   - En **Blob Storage**, crear la carpeta `incoming/` con subcarpetas por tienda (`store-a`, `store-b`, `store-c`) y carpetas globales (`products/`, `suppliers/`).  
   - En **ADLS Gen2**, crear las carpetas base:  
     `landing/`, `processed/`, `silver/`, `temporal_files/` y opcionalmente `gold/`.

3. **Configurar los pipelines en Azure Data Factory (ADF)**  
   - Ver importaciones de los pipelines en 'azure-data-pipelines-project/adf/'.
   - Implementar pipelines:
     - `pl_get_blob_files.json`  
     - `pl_ingest_blob_to_landing.json`  
     - `pl_main.json`
   - Configurar las conexiones (`Linked Services`) a:
     - Blob Storage (fuente)
     - ADLS Gen2 (destino)
     - Synapse (para notebooks)
   - Asegurar que los parámetros `storesFiles` y `storeName` estén correctamente enlazados entre los pipelines.

4. **Configurar notebooks de transformación en Synapse Analytics**  
   - Crear los notebooks:
     - `01_move_landing_to_processed` → genera la capa Bronze.  
     - `02_transform_silver` → limpia y valida los datos para la capa Silver.  
     - `03_model_gold` → carga los datos transformados hacia SQL Database (capa Gold).  
   - Vincular los notebooks con el pipeline principal `pl_main` en ADF.

5. **Configurar SQL Database**  
   - Creación de la base de datos SQL en Azure para la capa Gold (tablas agregadas y analíticas).
   - Soporte nativo con Power BI.

6. **Programar la ejecución automática**  
   - Crear un **Trigger programado** en ADF (por ejemplo, a las 2:00 a.m. hora Colombia) para ejecutar el pipeline `pl_main` diariamente.  
   - Validar que los logs muestren el correcto procesamiento de archivos y generación de tablas.

7. **Verificación final**  
   - Consultar en Synapse las tablas de la capa Gold.  
   - Confirmar que los datasets de Bronze y Silver se generen correctamente en formato Delta dentro del Data Lake.  
   - (Opcional) Conectar Power BI a la base de datos SQL para visualizar los resultados.


## Uso del proyecto

Esta solución fue desarrollada para **automatizar el proceso de integración y análisis de datos de ventas y clientes provenientes de múltiples tiendas**.  
El objetivo principal es **consolidar la información diaria de cada punto de venta en una única plataforma analítica en Azure**, garantizando la calidad, trazabilidad y disponibilidad de los datos para reportes y toma de decisiones.

En concreto, este pipeline permite:
- Recibir y procesar diariamente los archivos de ventas y clientes de cada tienda.  
- Unificar todos los datos en un modelo común (Common Data Model) con estructuras normalizadas.  
- Limpiar, validar y transformar los datos para crear datasets listos para análisis.  
- Exponer los resultados finales en una **base de datos SQL** de **Azure Synapse Analytics**, conectada a herramientas de visualización como **Power BI**.  

Gracias a esta arquitectura, las empresas pueden:
- Monitorear las ventas y los clientes de todas las tiendas con **actualización diaria automatizada**.  
- Detectar inconsistencias o errores en los datos fuente antes de su análisis.  
- Reducir tiempos manuales de carga y consolidación de información.  
- Contar con una base sólida para análisis históricos y reportes estratégicos.


## Contribuciones

Este es un proyecto personal desarrollado con fines educativos y de demostración profesional.  
Su objetivo principal es servir como una **muestra práctica de experiencia en Ingeniería de Datos en Microsoft Azure**, abarcando todas las etapas del ciclo de vida de datos.

En este proyecto se emplearon las siguientes tecnologías y servicios:

- **Azure Data Factory (ADF)**
- **Azure Blob Storage**
- **Azure Data Lake Storage Gen2 (ADLS)**
- **Azure Synapse Analytics**
- **PySpark / Python**
- **Delta Lake**
- **SQL**
- **Git & GitHub**

> Aunque este proyecto utiliza **notebooks de Synapse Analytics** para el procesamiento de datos, la misma solución podría haberse implementado con **Azure Databricks**.  
> Se eligió **Synapse** por motivos de **optimización de costos**, simplicidad operativa y su **conexión nativa con Power BI**, lo que facilita la exposición de los datos de la capa Gold para análisis y visualización empresarial.

Este repositorio busca reflejar el dominio de herramientas y buenas prácticas en **arquitecturas Lakehouse**, así como la capacidad de diseñar soluciones **automatizadas, escalables y orientadas a análisis empresarial** dentro del ecosistema de Azure.

Actualmente no se aceptan contribuciones externas, pero cualquier sugerencia o comentario es bienvenido a través de los *issues* del repositorio o contactando directamente al autor.


## Licencia

Este proyecto fue desarrollado por **Alejandro José Eljadue Tarud** con fines educativos y de demostración profesional.  
Su contenido puede ser utilizado libremente como referencia o inspiración, siempre que se otorgue el crédito correspondiente al autor.  

© 2025 Alejandro José Eljadue Tarud – Todos los derechos reservados.
