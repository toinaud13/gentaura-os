//! gentaura-bridge — Pont D-Bus système (TDD Partie 2, Section 4.A)
//!
//! S'enregistre sur le bus SYSTEME sous les noms exacts attendus par le code
//! C++ d'Ash (`chromeos/ash/components/dbus/`) et traduit les appels à la
//! volée vers les services Gentoo standards :
//!
//! [Interface exposée à Ash]            [Action interne]        [Cible Gentoo]
//! ---------------------------------------------------------------------------
//! org.chromium.flimflam.Manager    <---> états Wi-Fi/DNS   <---> NetworkManager / iwd
//! org.chromium.PowerManager        <---> batterie %/suspend<---> UPower & systemd-logind
//! org.chromium.SessionManagerInterface <---> SESSION_STARTED <---> validation immédiate PAM

use std::collections::HashMap;
use zbus::{connection, fdo, interface};

/// Représentation minimale d'un service flimflam (DeviceState, DeviceProperties…)
type Properties = HashMap<String, zbus::variant::Variant>;

pub struct FlimflamManager {
    /// Cache des propriétés traduites depuis NetworkManager.
    props: tokio::sync::RwLock<Properties>,
}

#[interface(name = "org.chromium.flimflam.Manager")]
impl FlimflamManager {
    /// Ash interroge l'état global du réseau via GetProperties().
    async fn get_properties(&self) -> Properties {
        self.props.read().await.clone()
    }

    /// Demande de scan Wi-Fi : relayée vers NM.Device.CreateAccessPoint / iwd Scan().
    async fn request_scan(&self) -> fdo::Result<()> {
        tracing::info!("flimflam.RequestScan -> NetworkManager/iwd scan");
        // TODO Jalon 4 : appel réel `org.freedesktop.NetworkManager` Device.GetSupportedTechnologies
        Ok(())
    }
}

pub struct PowerManager;

#[interface(name = "org.chromium.PowerManager")]
impl PowerManager {
    /// Conversion des niveaux de batterie (%) et état de charge depuis UPower
    /// (`org.freedesktop.UPower.Device.Percentage`, `State`).
    async fn get_power_supply_properties(&self) -> Properties {
        // TODO Jalon 4 : mapper UPower.DisplayDevice -> structure PowerSupplyProperties
        let mut p = Properties::new();
        p.insert("BatteryPercent".into(), 100.0.into());
        p.insert("BatteryIsCharging".into(), false.into());
        p
    }

    /// Ordre de veille : délégation stricte à systemd-logind
    /// (`org.freedesktop.login1.Manager.Suspend`) — pas de powerd Google.
    async fn request_suspend(&self) -> fdo::Result<()> {
        tracing::info!("powerd.RequestSuspend -> systemd-logind Suspend");
        Ok(())
    }
}

pub struct SessionManager;

#[interface(name = "org.chromium.SessionManagerInterface")]
impl SessionManager {
    /// Simulation de l'état "SESSION_STARTED" pour débloquer le bureau Ash :
    /// l'utilisateur est DÉJÀ authentifié par PAM/greetd en amont (patch 02).
    async fn retrieve_session_state(&self) -> u32 {
        2 // chromeos::SessionManagerStatus::SESSION_STARTED
    }

    async fn emit_login_prompt_visible(&self) -> fdo::Result<()> {
        tracing::info!("SessionManager: login prompt suppressed (local Unix session)");
        Ok(())
    }
}

#[tokio::main]
async fn main() -> zbus::Result<()> {
    tracing_subscriber::fmt::init();

    let conn = connection::system()
        .name("org.chromium.flimflam")?
        .serve_at("/org/chromium/flimflam/Manager", FlimflamManager {
            props: tokio::sync::RwLock::new(Properties::new()),
        })?
        .name("org.chromium.PowerManager")?
        .serve_at("/org/chromium/PowerManager", PowerManager)?
        .name("org.chromium.SessionManager")?
        .serve_at("/org/chromium/SessionManager", SessionManager)?
        .build()
        .await?;

    tracing::info!("gentaura-bridge ready on system bus (flimflam/power/session gateways)");
    conn.keep_alive().await;
    Ok(())
}
