use penrose::{
    builtin::{
        actions::{exit, key_handler, modify_with, send_layout_message, spawn},
        layout::{
            messages::{ExpandMain, IncMain, ShrinkMain},
            transformers::{Gaps, ReserveTop},
            MainAndStack, Monocle,
        },
    },
    core::{
        bindings::{parse_keybindings_with_xmodmap, KeyCode, KeyEventHandler},
        hooks::{EventHook, StateHook},
        layout::LayoutStack,
        Config, State, WindowManager,
    },
    extensions::hooks::add_ewmh_hooks,
    map, stack,
    x::{XConn, XEvent},
    x11rb::RustConn,
    Result,
};
use penrose_ui::{status_bar, Position, TextStyle};
use std::{borrow::BorrowMut, collections::HashMap, sync::Mutex};
use tracing_subscriber::{self, prelude::*};

const FONT: &str = "ProFontIIx Nerd Font";
const BLACK: u32 = 0x282828ff;
const WHITE: u32 = 0xebdbb2ff;
// const GREY: u32 = 0x3c3836ff;
const BLUE: u32 = 0x458588ff;

// gruvbox
const BG0: u32 = 0x282828d1;
const BG1: u32 = 0x3c3836d1;
const BG2: u32 = 0x504945d1;
const BG3: u32 = 0x665c54d1;
const AQUA: u32 = 0x8ec07cd1;
const FG0: u32 = 0xfbf1c7d1;
const GRAY: u32 = 0x928374d1;

const MAX_MAIN: u32 = 1;
const RATIO: f32 = 0.6;
const RATIO_STEP: f32 = 0.1;
const OUTER_PX: u32 = 0;
const INNER_PX: u32 = 0;
const BAR_HEIGHT_PX: u32 = 15;

#[derive(Clone, Copy, Hash, PartialEq, Eq, Debug)]
enum Mode {
    Normal,
    Locked,
    Resize,
    Move,
    Focus,
}

type Bindings = HashMap<KeyCode, Box<dyn KeyEventHandler<RustConn>>>;

struct KeyBinderState {
    bindings: HashMap<Mode, Bindings>,
    current_mode: Mode,
    fallback_bindings: Bindings,
}

impl KeyBinderState {
    fn with_bindings() -> Result<Self> {
        let locked = parse_keybindings_with_xmodmap(map! {
            map_keys: |k: &str| k.to_string();

            "A-g" => key_handler(Self::toggle_locked),
        })?;

        let normal = parse_keybindings_with_xmodmap(map! {
            map_keys: |k: &str| k.to_string();

            "A-g" => key_handler(Self::toggle_locked),
            "A-h" => key_handler(Self::left_desktop),
            "A-Return" => spawn("alacritty"), // TODO: don't spawn a new alacritty process
            "A-Escape" => exit(),
        })?;
        let s = Self {
            bindings: map! {
                Mode::Locked => locked,
                Mode::Normal => normal,
            },
            current_mode: Mode::Normal,
            fallback_bindings: Self::fallback_bindings()?,
        };

        Ok(s)
    }

    fn fallback_bindings() -> Result<Bindings> {
        let raw_bindings = map! {
            map_keys: |k: &str| k.to_string();

            "A-j" => modify_with(|cs| cs.focus_down()),
            "A-k" => modify_with(|cs| cs.focus_up()),
            "A-S-j" => modify_with(|cs| cs.swap_down()),
            "A-S-k" => modify_with(|cs| cs.swap_up()),
            "A-q" => modify_with(|cs| cs.kill_focused()),
            "A-bracketright" => modify_with(|cs| cs.next_layout()),
            "A-bracketleft" => modify_with(|cs| cs.previous_layout()),
            "A-S-Up" => send_layout_message(|| IncMain(1)),
            "A-S-Down" => send_layout_message(|| IncMain(-1)),
            "A-S-Right" => send_layout_message(|| ExpandMain),
            "A-S-Left" => send_layout_message(|| ShrinkMain),
            "A-semicolon" => spawn("dmenu_run"),
            "A-Return" => spawn("alacritty"),
            "A-Escape" => exit(),
        };
        parse_keybindings_with_xmodmap(raw_bindings)
    }

    fn toggle_locked(state: &mut State<RustConn>, x: &RustConn) -> Result<()> {
        let e_arc = state.extension::<Mutex<KeyBinderState>>()?;
        let e_borrow = e_arc.borrow();
        let mut e = e_borrow.lock().unwrap();

        if let Mode::Locked = e.current_mode {
            e.current_mode = Mode::Normal;
        } else {
            e.current_mode = Mode::Locked;
        }

        drop(e);
        KeyBinder.bind(x, state)?;
        Ok(())
    }

    fn left_desktop(state: &mut State<RustConn>, x: &RustConn) -> Result<()> {
        Ok(())
    }
}

struct KeyBinder;

impl KeyBinder {
    fn bind(&self, conn: &RustConn, state: &State<RustConn>) -> Result<()> {
        let s_arc = state.extension::<Mutex<KeyBinderState>>()?;
        let s = s_arc.borrow();
        let s = s.lock().unwrap();
        let key_bindings = s
            .bindings
            .get(&s.current_mode)
            .unwrap_or(&s.fallback_bindings);

        let key_codes: Vec<_> = key_bindings.keys().copied().collect();

        // let mouse_states: Vec<_> = mouse_bindings
        //     .keys()
        //     .map(|(_, state)| state.clone())
        //     .collect();

        conn.grab(&key_codes, Default::default())?;
        Ok(())
    }
}

impl StateHook<RustConn> for KeyBinder {
    fn call(&mut self, state: &mut State<RustConn>, x: &RustConn) -> Result<()> {
        KeyBinder.bind(x, state)?;

        Ok(())
    }
}

impl EventHook<RustConn> for KeyBinder {
    fn call(&mut self, event: &XEvent, state: &mut State<RustConn>, x: &RustConn) -> Result<bool> {
        let binder = state.extension::<Mutex<KeyBinderState>>()?;
        let binder = binder.borrow();
        let mut binder = binder.lock().unwrap();
        let mode = binder.current_mode;
        let bindings = binder.bindings.get_mut(&mode).unwrap();
        match event {
            // A-g
            XEvent::KeyPress(KeyCode { code: 42, mask: 8 }) => {
                drop(binder);
                KeyBinderState::toggle_locked(state, x)?;
            }
            XEvent::KeyPress(k) => {
                if let Some(action) = bindings.get_mut(k) {
                    action.call(state, x)?;
                }
            }
            // XEvent::ClientMessage(_) => todo!(),
            // XEvent::ConfigureNotify(_) => todo!(),
            // XEvent::ConfigureRequest(_) => todo!(),
            // XEvent::Enter(_) => todo!(),
            // XEvent::Expose(_) => todo!(),
            // XEvent::FocusIn(_) => todo!(),
            // XEvent::Destroy(_) => todo!(),
            // XEvent::Leave(_) => todo!(),
            // XEvent::MappingNotify => todo!(),
            // XEvent::MapRequest(_) => todo!(),
            // XEvent::MouseEvent(_) => todo!(),
            // XEvent::PropertyNotify(_) => todo!(),
            // XEvent::RandrNotify => todo!(),
            // XEvent::ResizeRequest(_) => todo!(),
            // XEvent::ScreenChange => todo!(),
            // XEvent::UnmapNotify(_) => todo!(),
            _ => {
            },
        }
        Ok(true)
    }
}

// struct LayoutTopG {
//     layouts:
// }

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
    let style = TextStyle {
        fg: FG0.into(),
        bg: Some(BG0.into()),
        padding: (2, 2),
    };

    let bar = status_bar(BAR_HEIGHT_PX, FONT, 8, style, BG1, GRAY, Position::Top).unwrap();

    let mut config = add_ewmh_hooks(Config {
        default_layouts: layouts(),
        border_width: 1,
        focused_border: AQUA.into(),
        normal_border: BG1.into(),
        // focus_follow_mouse: false,
        ..Config::default()
    });
    config.compose_or_set_event_hook(KeyBinder);
    config.compose_or_set_startup_hook(KeyBinder);

    let mut wm = bar.add_to(WindowManager::new(
        config,
        Default::default(),
        HashMap::new(),
        conn,
    )?);

    wm.state
        .add_extension(Mutex::new(KeyBinderState::with_bindings()?));

    wm.run()?;
    Ok(())
}

