use super::{client, emit, status_error, IntegrationUpdate};
use crate::secrets;
use serde_json::{json, Value};
use tauri::AppHandle;

// ── GitHub ────────────────────────────────────────────────────────────────────

pub(super) async fn poll_github(app: AppHandle) {
    let Some(token) = secrets::get("github-token") else {
        return;
    };
    let http = client();

    let user = http
        .get("https://api.github.com/user")
        .header("Authorization", format!("Bearer {token}"))
        .header("Accept", "application/vnd.github+json")
        .header("User-Agent", "Perch")
        .send()
        .await;
    let Ok(response) = user else { return };
    if !response.status().is_success() {
        emit(
            &app,
            IntegrationUpdate {
                id: "integration_github",
                data: json!({}),
                error: Some(status_error(
                    response.status().as_u16(),
                    "Token lacks the needed scope",
                )),
                event: None,
            },
        );
        return;
    }
    let json: Value = response.json().await.unwrap_or(json!({}));
    let public = json
        .get("public_repos")
        .and_then(Value::as_i64)
        .unwrap_or(0);
    let private = json
        .get("owned_private_repos")
        .or_else(|| json.get("total_private_repos"))
        .and_then(Value::as_i64)
        .unwrap_or(0);

    let repos = http
        .get("https://api.github.com/user/repos?per_page=100&affiliation=owner&sort=pushed")
        .header("Authorization", format!("Bearer {token}"))
        .header("Accept", "application/vnd.github+json")
        .header("User-Agent", "Perch")
        .send()
        .await;
    let stars: i64 = match repos {
        Ok(r) if r.status().is_success() => r
            .json::<Value>()
            .await
            .ok()
            .and_then(|v| v.as_array().cloned())
            .map(|list| {
                list.iter()
                    .filter_map(|r| r.get("stargazers_count").and_then(Value::as_i64))
                    .sum()
            })
            .unwrap_or(0),
        _ => 0,
    };

    emit(
        &app,
        IntegrationUpdate {
            id: "integration_github",
            data: json!({ "totalRepos": public + private, "totalStars": stars }),
            error: None,
            event: None,
        },
    );
}
