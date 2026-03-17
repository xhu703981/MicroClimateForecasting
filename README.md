# BME280 Microclimate Forecasting

An end-to-end IoT time-series forecasting system — from embedded firmware to cloud storage to machine learning — that benchmarks three models across multiple prediction horizons for real-world microclimate temperature forecasting.

## System Architecture

```
BME280 Sensor (I2C)
  → Nordic nRF52 (Zephyr RTOS, 10-sec sampling)
  → BLE / Nordic UART Service (NUS)
  → iOS App (BLE Central, HTTP POST)
  → AWS EC2 (FastAPI + PostgreSQL)
  → Export Script
  → sensor_data.csv
  → ML Models (XGBoost / LSTM / Transformer)
```

A BME280 environmental sensor is connected via I2C to a Nordic nRF52 development board running Zephyr RTOS. The firmware reads temperature, humidity, and barometric pressure every 10 seconds and broadcasts the data over BLE using the Nordic UART Service (NUS). A custom iOS app acts as a BLE central, parses incoming sensor strings, and forwards readings via HTTP POST to a FastAPI backend running on AWS EC2. Readings are stored in a PostgreSQL database and exported to CSV for model training.

**Design decision:** The sampling interval was deliberately set to 10 seconds (rather than a faster rate) to balance data resolution with storage efficiency, yielding approximately 8,640 readings per day during continuous operation.

## Task

Given a window of historical sensor readings, predict the temperature at a future time horizon.

- **Input features:** temperature (°C), humidity (%), barometric pressure (hPa)
- **Target:** temperature at t + horizon
- **Horizons evaluated:** 30 minutes, 1 hour, 1.5 hours
- **Dataset:** ~7 days of 10-second resolution data (64,000+ rows), collected March 2026
- **Train/Val/Test split:** 60% / 20% / 20% (chronological)
- **Baseline:** Linear extrapolation from the last 10 observed steps

## Results

### 30-Minute Prediction

| Model | RMSE | Baseline | Improvement |
|-------|------|----------|-------------|
| LSTM | 0.745°C | 2.59°C | 71.2% |
| XGBoost | 0.764°C | 2.59°C | 70.5% |
| Transformer | 0.978°C | 2.59°C | 62.3% |

### 1-Hour Prediction

| Model | RMSE | Baseline | Improvement |
|-------|------|----------|-------------|
| LSTM | 1.243°C | 2.662°C | 53.4% |
| XGBoost | 1.941°C | 2.662°C | 27.1% |
| Transformer | 2.696°C | 2.662°C | ~0% |

### 1.5-Hour Prediction

| Model | RMSE | Baseline | Improvement |
|-------|------|----------|-------------|
| LSTM | 1.514°C | 2.841°C | 46.7% |
| XGBoost | 1.802°C | 2.841°C | 36.6% |
| Transformer | 1.711°C | 2.841°C | 39.8% |

## Key Findings

**LSTM is the strongest model across all horizons.** It achieves the best RMSE at every prediction window, with the largest advantage at short horizons (71.2% improvement at 30 minutes).

**Transformer underperforms on this task — by design.** Transformer's self-attention mechanism is best suited for high-dimensional data with complex long-range dependencies. With only 3 input features and smooth temporal dynamics, LSTM's sequential inductive bias is better matched to this problem. This is consistent with findings in the time-series literature.

**Transformer partially recovers at longer horizons.** At 1 hour, Transformer barely beats the linear baseline (~0%). At 1.5 hours, it recovers to 39.8% — suggesting that longer input sequences give attention more signal to work with.

**XGBoost degrades faster than LSTM at longer horizons.** XGBoost is nearly on par with LSTM at 30 minutes (70.5% vs 71.2%), but falls behind at 1 hour (27.1%) and 1.5 hours (36.6%). This reflects the limitation of flat feature vectors for capturing long-range temporal patterns.

**All models exhibit overfitting.** With only 7 days of data and high temporal autocorrelation in IoT sensor readings, train loss decreases consistently while validation loss plateaus. This motivates continued data collection.

## Data Pipeline

### Embedded Firmware (Zephyr RTOS / Nordic nRF52)

The firmware is written in C using Zephyr RTOS and runs on a Nordic nRF52 development board.

Key implementation details:
- BME280 connected via I2C, read using Zephyr sensor API
- Data transmitted over BLE using Nordic UART Service (NUS)
- Sampling interval: 10 seconds (configurable via `BME280_SAMPLE_INTERVAL_MS`)
- Output format: `T=XX.XXC H=XX.XX% P=XXXX.XXhPa` parsed by iOS app via regex

```c
sensor_sample_fetch(bme280_dev);
sensor_channel_get(bme280_dev, SENSOR_CHAN_AMBIENT_TEMP, &temp);
sensor_channel_get(bme280_dev, SENSOR_CHAN_HUMIDITY, &hum);
sensor_channel_get(bme280_dev, SENSOR_CHAN_PRESS, &press);

snprintk(nus_msg, sizeof(nus_msg), "T=%.2fC H=%.2f%% P=%.2fhPa\r\n", ...);
bt_nus_send(NULL, (uint8_t *)nus_msg, len);
```

### iOS App (BLE Central)

A custom iOS app connects to the nRF52 as a BLE central, parses incoming sensor strings, and forwards each reading via HTTP POST to the EC2 backend.

### EC2 Backend (FastAPI + PostgreSQL)

The backend is built with FastAPI and stores readings in a PostgreSQL database on AWS EC2.

Key endpoints:

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/experiment-sessions` | Create a new experiment session |
| GET | `/experiment-sessions` | List all sessions |
| POST | `/sensor-readings` | Ingest a single reading |
| POST | `/sensor-readings/batch` | Batch ingest readings |
| GET | `/sensor-readings` | Query readings by session and time range |

Sensor readings are stored in a PostgreSQL database on EC2. A lightweight export script queries the database and writes readings to `sensor_data.csv` for model training.

## Model Details

### LSTM
- Input: sliding window x 3 features at 10-second resolution
- Architecture: 2-layer LSTM, hidden size 64, dropout 0.2
- Training: Adam optimizer, early stopping on validation loss (checkpoint saved)
- Scaler: MinMaxScaler fitted on training set only

### Transformer
- Input: sliding window x 3 features at 10-second resolution
- Architecture: d_model=32, 4 attention heads, 3 encoder layers, sinusoidal positional encoding, dropout 0.1
- Training: WeightedRandomSampler to reduce influence of anomalous high-temperature events
- Scaler: MinMaxScaler fitted on training set only

### XGBoost
- Input: 5-minute resampled data with domain-specific feature engineering
- Architecture: n_estimators=500, learning_rate=0.04, max_depth=3, early stopping on validation set

> Note: XGBoost operates on 5-minute resampled data with meteorological feature engineering, while LSTM and Transformer use raw 10-second data. RMSE values are comparable in magnitude but reflect different input representations.

## Feature Engineering (XGBoost)

```python
# Dewpoint via Magnus formula
a, b = 17.27, 237.7
alpha    = (a * temperature) / (b + temperature) + log(humidity / 100)
dewpoint = (b * alpha) / (a - alpha)

# Dewpoint deficit - proxy for evaporative cooling potential
deficit = temperature - dewpoint

# Tendency features - rate of change over past 30 minutes
pressure_tendency    = pressure_hpa.diff(6)
humidity_tendency    = deficit.diff(6)
temperature_tendency = temperature_c.diff(6)

# Cyclic time encoding
hour_sin = sin(2 * pi * hour / 24)
hour_cos = cos(2 * pi * hour / 24)
```

## Repository Structure

```
data/
    sensor_data.csv                # Raw sensor readings (exported from PostgreSQL)
data_pipeline/
    firmware/                      # Zephyr RTOS firmware (C) for Nordic nRF52
    ios_app/                       # iOS BLE central app (Swift)
    ec2_receiver/                  # FastAPI + PostgreSQL backend
models/
    lstm.ipynb                     # LSTM training and evaluation
    transformer.ipynb              # Transformer training and evaluation
    xgboost.ipynb                  # XGBoost with feature engineering
README.md
```

## Requirements

```bash
pip install torch xgboost scikit-learn pandas numpy matplotlib torchinfo
```

For firmware: Nordic nRF Connect SDK with Zephyr RTOS. See `data_pipeline/firmware/` for build instructions.

For backend: `pip install fastapi sqlalchemy psycopg2-binary uvicorn python-dotenv`

## Limitations and Future Work

- **Data volume:** 7 days of data limits generalization. Continued collection is underway.
- **Single sensor:** All data from one indoor location. Anomalous readings from direct heat exposure (up to 53°C) introduce distribution shift between train and test sets.
- **Future:** Deploy best model (LSTM) on EC2 for real-time inference; explore multi-step forecasting; add second sensor for spatial comparison.

---