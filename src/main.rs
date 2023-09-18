use penrose::{
    builtin::{
        actions::{exit, modify_with, send_layout_message, spawn},
        layout::{
            messages::{ExpandMain, IncMain, ShrinkMain},
            transformers::{Gaps, ReserveTop},
            MainAndStack, Monocle,
        },
    },
    core::{
        bindings::{parse_keybindings_with_xmodmap, KeyEventHandler},
        layout::LayoutStack,
        Config, WindowManager,
    },
    extensions::hooks::add_ewmh_hooks,
    map, stack,
    x11rb::RustConn,
    Result,
};
use penrose_ui::{status_bar, Position, TextStyle};
use std::collections::HashMap;
use tracing_subscriber::{self, prelude::*};

const FONT: &str = "ProFontIIx Nerd Font";
const BLACK: u32 = 0x282828ff;
const WHITE: u32 = 0xebdbb2ff;
const GREY: u32 = 0x3c3836ff;
const BLUE: u32 = 0x458588ff;

const MAX_MAIN: u32 = 1;
const RATIO: f32 = 0.6;
const RATIO_STEP: f32 = 0.1;
const OUTER_PX: u32 = 5;
const INNER_PX: u32 = 5;
const BAR_HEIGHT_PX: u32 = 18;

fn raw_key_bindings() -> HashMap<String, Box<dyn KeyEventHandler<RustConn>>> {
    let mut raw_bindings = map! {
        map_keys: |k: &str| k.to_string();

        "A-j" => modify_with(|cs| cs.focus_down()),
        "A-k" => modify_with(|cs| cs.focus_up()),
        "A-S-j" => modify_with(|cs| cs.swap_down()),
        "A-S-k" => modify_with(|cs| cs.swap_up()),
        "A-q" => modify_with(|cs| cs.kill_focused()),
        "A-Tab" => modify_with(|cs| cs.toggle_tag()),
        "A-bracketright" => modify_with(|cs| cs.next_layout()),
        "A-bracketleft" => modify_with(|cs| cs.previous_layout()),
        // "M-grave" => modify_with(|cs| cs.next_layout()),
        // "M-S-grave" => modify_with(|cs| cs.previous_layout()),
        "A-S-Up" => send_layout_message(|| IncMain(1)),
        "A-S-Down" => send_layout_message(|| IncMain(-1)),
        "A-S-Right" => send_layout_message(|| ExpandMain),
        "A-S-Left" => send_layout_message(|| ShrinkMain),
        "A-semicolon" => spawn("dmenu_run"),
        "A-Return" => spawn("alacritty"),
        "A-Escape" => exit(),
    };

    for tag in &["1", "2", "3", "4", "5", "6", "7", "8", "9"] {
        raw_bindings.extend([
            (
                format!("A-{tag}"),
                modify_with(move |client_set| client_set.focus_tag(tag)),
            ),
            (
                format!("A-S-{tag}"),
                modify_with(move |client_set| client_set.move_focused_to_tag(tag)),
            ),
        ]);
    }

    raw_bindings
}

fn layouts() -> LayoutStack {
    stack!(
        MainAndStack::side(MAX_MAIN, RATIO, RATIO_STEP),
        MainAndStack::side_mirrored(MAX_MAIN, RATIO, RATIO_STEP),
        MainAndStack::bottom(MAX_MAIN, RATIO, RATIO_STEP),
        Monocle::boxed()
    )
    .map(|layout| ReserveTop::wrap(Gaps::wrap(layout, OUTER_PX, INNER_PX), BAR_HEIGHT_PX))
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("info")
        .finish()
        .init();

    let conn = RustConn::new()?;
    let key_bindings = parse_keybindings_with_xmodmap(raw_key_bindings())?;
    let style = TextStyle {
        fg: WHITE.into(),
        bg: Some(BLACK.into()),
        padding: (2, 2),
    };

    let bar = status_bar(BAR_HEIGHT_PX, FONT, 8, style, BLUE, GREY, Position::Top).unwrap();

    let config = add_ewmh_hooks(Config {
        default_layouts: layouts(),
        ..Config::default()
    });
    let wm = bar.add_to(WindowManager::new(
        config,
        key_bindings,
        HashMap::new(),
        conn,
    )?);

    wm.run()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    // #[test]
    fn bindings_parse_correctly_with_xmodmap() {
        let res = parse_keybindings_with_xmodmap(raw_key_bindings());

        if let Err(e) = res {
            panic!("{e}");
        }
    }
}
