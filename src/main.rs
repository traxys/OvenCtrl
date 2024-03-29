use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};

use anyhow::Context;
use axum::{extract::State, routing::post, Json, Router};
use time::OffsetDateTime;
use tower_http::trace::TraceLayer;
use tracing::Level;
use tracing_subscriber::EnvFilter;
use url::Url;

#[derive(serde::Deserialize, Debug)]
pub struct OvenClient {
    pub address: String,
    pub port: u16,
    pub user_agent: String,
}

#[derive(serde::Deserialize, Debug)]
#[serde(rename_all = "lowercase")]
pub enum OvenDirection {
    Incoming,
    Outgoing,
}

#[derive(serde::Deserialize, Debug)]
pub enum OvenProtocol {
    WebRTC,
    RTMP,
    SRT,
    LLHLS,
    Thumbnail,
}

#[derive(serde::Deserialize, Debug)]
#[serde(rename_all = "lowercase")]
pub enum OvenStatus {
    Closing,
    Opening,
}

#[derive(serde::Deserialize, Debug)]
pub struct OvenRequest {
    pub direction: OvenDirection,
    pub protocol: OvenProtocol,
    pub status: OvenStatus,
    pub url: Url,
    pub new_url: Option<Url>,
    #[serde(deserialize_with = "time::serde::iso8601::deserialize")]
    pub time: OffsetDateTime,
}

#[derive(serde::Deserialize, Debug)]
pub struct OvenAdmission {
    pub client: OvenClient,
    pub request: OvenRequest,
}

#[derive(serde::Serialize, Debug)]
pub struct OvenClosingResponse {}

#[derive(serde::Serialize, Debug)]
pub struct OvenOpeningResponse {
    pub allowed: bool,
    pub new_url: Option<Url>,
    pub lifetime: Option<u64>,
    pub reason: Option<String>,
}

#[derive(serde::Serialize, Debug)]
#[serde(untagged)]
pub enum OvenResponse {
    Closing(OvenClosingResponse),
    Opening(OvenOpeningResponse),
}

impl From<OvenOpeningResponse> for Json<OvenResponse> {
    fn from(value: OvenOpeningResponse) -> Self {
        Json(OvenResponse::Opening(value))
    }
}

impl From<OvenClosingResponse> for Json<OvenResponse> {
    fn from(value: OvenClosingResponse) -> Self {
        Json(OvenResponse::Closing(value))
    }
}

fn handle_opening_admission(
    state: &OvenCtrlConfig,
    payload: OvenAdmission,
) -> anyhow::Result<OvenOpeningResponse> {
    match payload.request.direction {
        OvenDirection::Incoming => {
            #[derive(serde::Deserialize)]
            struct IngestQuery {
                name: String,
                key: String,
            }

            let query = payload
                .request
                .url
                .query()
                .context("no query parameters present")?;

            let query = serde_urlencoded::from_str::<IngestQuery>(query)?;
            let expected_key = state
                .streamers
                .get(&query.name)
                .with_context(|| format!("unknown streamer: {}", query.name))?;

            if expected_key != &query.key {
                anyhow::bail!("invalid key for streamer {}", query.name)
            }

            let room = payload
                .request
                .url
                .path_segments()
                .with_context(|| format!("url '{:?}' has no segments", payload.request.url))?
                .nth(1)
                .with_context(|| {
                    format!("url '{:?}' is laking a second segment", payload.request.url)
                })?;

            let allowed_streams = state.allowed_streams.get(&query.name).with_context(|| {
                format!(
                    "streamer '{}' does not have access to any rooms",
                    query.name
                )
            })?;

            if !allowed_streams.contains(room) {
                anyhow::bail!(
                    "streamer {} does not have access to room {room}",
                    query.name
                )
            }
        }
        OvenDirection::Outgoing => {}
    }

    Ok(OvenOpeningResponse {
        allowed: true,
        lifetime: None,
        new_url: None,
        reason: None,
    })
}

#[tracing::instrument(skip(state))]
async fn admission(
    state: State<Arc<OvenCtrlConfig>>,
    payload: Json<OvenAdmission>,
) -> Json<OvenResponse> {
    tracing::trace!("Received admission request");

    match payload.request.status {
        OvenStatus::Closing => OvenClosingResponse {}.into(),
        OvenStatus::Opening => match handle_opening_admission(&state, payload.0) {
            Err(err) => OvenOpeningResponse {
                allowed: false,
                new_url: None,
                lifetime: None,
                reason: Some(err.to_string()),
            },
            Ok(rsp) => rsp,
        }
        .into(),
    }
}

#[derive(serde::Deserialize, Debug)]
struct OvenCtrlConfig {
    /// Streamer name to token
    #[serde(default)]
    streamers: HashMap<String, String>,
    /// Streamer name to allowed streams
    #[serde(default)]
    allowed_streams: HashMap<String, HashSet<String>>,
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::builder()
                .with_default_directive(Level::INFO.into())
                .from_env_lossy(),
        )
        .init();

    let settings = config::Config::builder()
        .add_source(config::File::with_name(
            &std::env::args().nth(1).context("Missing configuration")?,
        ))
        .add_source(config::Environment::with_prefix("OVEN_CTRL"))
        .build()?
        .try_deserialize::<OvenCtrlConfig>()?;

    let app = Router::new()
        .route("/oven/admission", post(admission))
        .with_state(Arc::new(settings))
        .layer(TraceLayer::new_for_http());

    let listener = tokio::net::TcpListener::bind(("0.0.0.0", 3000)).await?;

    tracing::info!("Starting oven-ctrl");

    axum::serve(listener, app).await.map_err(Into::into)
}
