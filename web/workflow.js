/* Guided workspace: presentation only. Existing Lua callbacks validate every edit. */
(function () {
  'use strict';
  function assess(project, context = {}) {
    const actors = project.actors || [], shots = project.cameraShots || [];
    const keys = project.keyframes || [];
    const hasCamera = keys.length > 0 || shots.some(s => (s.frames || []).length > 0 || (s.rig?.mode && s.rig.mode !== 'manual')) || (project.cameraRig?.mode && project.cameraRig.mode !== 'manual');
    const first = Number(project.playback?.first ?? 0), last = Number(project.playback?.last ?? project.duration);
    const missing = actors.filter(a => a.modelAvailable === false || a._missing);
    const problems = [];
    if (!hasCamera) problems.push({ step: 'camera', text: 'Ajoute une position de caméra.' });
    if (missing.length) problems.push({ step: 'subject', text: 'Modèle indisponible : ' + missing.map(a => a.model).join(', ') + '. Recharge le modèle ou retire ce sujet.' });
    if (!Number.isFinite(first) || !Number.isFinite(last) || first < 0 || last <= first || last > project.duration) problems.push({ step: 'camera', range: true, text: 'La plage de lecture doit rester dans la durée du projet.' });
    if (context.editing) problems.push({ step: 'route', text: 'Valide ou annule le trajet en cours avant de filmer.' });
    if (context.viewer) problems.push({ text: 'Tu regardes une session partagée. L’hôte pilote le tournage.' });
    if (context.saving) problems.push({ text: 'Attends la fin de la sauvegarde.' });
    const warnings = [];
    for(const actor of actors){
      const spans=(actor.actions||[]).filter(a=>a.duration>0&&['move','animation','recording'].includes(a.type)).sort((a,b)=>a.time-b.time);
      let end=-1;for(const clip of spans){if(clip.time<end-.001){warnings.push({step:'route',text:'Actions superposées pour '+actor.model+' : vérifie leur priorité à la lecture.'});break;}end=Math.max(end,clip.time+clip.duration);}
    }
    if (context.dirty) warnings.push({ save: true, text: 'Enregistre les dernières modifications avant ta prise.' });
    if (!context.previewed) warnings.push({ preview: true, text: 'Relis la scène pour vérifier le cadrage, le sol et les obstacles.' });
    return { hasCamera: Boolean(hasCamera), actors: actors.length, movement: actors.some(a => (a.actions || []).some(c => ['move', 'route', 'recording'].includes(c.type))), missing: missing.length, first, last, problems, warnings, ready: problems.length === 0 };
  }
  if (typeof module === 'object' && module.exports) module.exports = { assess };
  if (typeof document === 'undefined') return;

  const q = id => document.getElementById(id), root = q('director');
  let step = 'camera', guided = true, previewed = false, queued = false, switching = false, launching = false;
  const steps = [['camera', 'Caméra'], ['subject', 'Sujet'], ['route', 'Actions'], ['check', 'Vérifier'], ['film', 'Filmer']];
  const nav = document.createElement('nav'); nav.className = 'workflow-nav'; nav.setAttribute('aria-label', 'Étapes du tournage');
  for (const [id, label] of steps) {
    const b = document.createElement('button'); b.type = 'button'; b.dataset.step = id;
    b.innerHTML = '<span class="workflow-number">' + (steps.findIndex(s => s[0] === id) + 1) + '</span><span>' + label + '</span>';
    b.onclick = () => choose(id); nav.append(b);
  }
  const mode = document.createElement('button'); mode.id = 'workflowMode'; mode.className = 'workflow-mode'; mode.type = 'button'; mode.onclick = () => {
    if (root.classList.contains('editing-route')) return showStatus('Valide ou annule le trajet avant de changer de mode.');
    guided = !guided; root.classList.toggle('guided', guided); root.classList.remove('workflow-review'); render(); updateFraming();
  }; nav.append(mode); root.append(nav);
  const right = root.querySelector('.right-panel');
  const guide = document.createElement('section'); guide.className = 'workflow-guide'; guide.setAttribute('aria-label', 'Aide à l’étape');
  guide.innerHTML = '<span id="workflowEyebrow"></span><h2 id="workflowTitle"></h2><p id="workflowHint"></p><div class="workflow-actions"><button id="workflowPrimary" type="button"></button><button id="workflowAtmosphere" type="button">Météo et lumière</button></div><p id="workflowReason" role="status"></p><button id="workflowNext" class="workflow-next" type="button"></button>';
  right.prepend(guide);
  const review = document.createElement('section'); review.className = 'workflow-review-pane'; review.id = 'workflowReview';
  review.innerHTML = '<h3 id="workflowCheckTitle">Avant la prise</h3><div id="workflowChecks"></div><div id="workflowIssues"></div><div id="workflowRecording" class="workflow-recording"><strong>OBS enregistre la vidéo</strong><ol><li>Lance l’enregistrement dans OBS.</li><li>Clique sur « Lancer la prise propre ».</li><li>L’interface disparaît après le compte à rebours.</li><li><kbd>F9</kbd> arrête la prise ; termine ensuite l’enregistrement OBS.</li></ol><p>Director anime ta scène. Il ne crée pas de fichier vidéo et ne peut pas vérifier qu’OBS enregistre.</p></div>';
  right.append(review);
  // In guided mode the header leads to the checklist; only the explicit final
  // action launches capture. Free mode keeps the original one-click shortcut.
  q('captureButton').addEventListener('click', event => {
    if (!guided) return;
    event.preventDefault(); event.stopImmediatePropagation(); choose('film');
  }, true);
  q('workflowAtmosphere').onclick = () => { selectSceneTab(lookTabActive ? step === 'subject' : 'look'); schedule(); };
  q('workflowNext').onclick = () => choose(steps[Math.min(4, steps.findIndex(s => s[0] === step) + 1)][0]);
  q('workflowPrimary').onclick = async () => {
    if (launching) return;
    if (step === 'camera') q('addKeyframeButton').click();
    else if (step === 'subject') q('browseModelsButton').click();
    else if (step === 'route') {
      const a = project.actors.find(a => a.id === selectedActorId);
      if(a){const details=[...q('actorInspector').querySelectorAll('details')].find(d=>d.querySelector('.free-move-action'));if(details)details.open=true;const move=q('actorInspector').querySelector('.free-move-action');move?.scrollIntoView({block:'nearest'});move?.focus();showStatus('Vise une destination avec la caméra, puis ajoute le déplacement au temps choisi.');}
    } else if (step === 'check') q('previewButton').click();
    else {
      if (!state().ready) return render();
      launching = true; render();
      const result = await post('capture'); launching = false;
      if (!result.ok) showStatus(result.message || 'La prise ne peut pas démarrer.');
      schedule();
    }
  };
  function state() { return assess(project, { editing: root.classList.contains('editing-route'), viewer: sessionRole === 'viewer', saving: savePending, dirty: saveDirty, previewed }); }
  function choose(id) {
    if (!steps.some(s => s[0] === id)) return;
    if (root.classList.contains('editing-route')) return showStatus('Valide ou annule le trajet pour passer à une autre étape.');
    step = id; switching = true;
    root.classList.remove('collapsed-left', 'collapsed-right');
    selectSceneTab(id !== 'camera'); switching = false;
    render(); updateFraming();
  }
  function schedule() {
    if (queued) return; queued = true;
    queueMicrotask(() => { queued = false; render(); });
  }
  const copy = {
    camera: ['Compose ton plan', 'Place la caméra avec les touches de déplacement et le clic droit. Ajoute une position, avance dans la timeline, puis ajoute la suivante.', 'Ajouter cette position'],
    subject: ['Place ton sujet', 'Choisis un personnage, un véhicule ou un objet. Déplace-le dans la vue avec la souris. Une scène de paysage peut rester sans sujet.', 'Choisir un modèle'],
    route: ['Donne vie à la scène', 'Sélectionne un sujet, vise une destination avec la caméra et ajoute son déplacement au temps choisi. Pour un personnage, tu peux aussi choisir une animation. Une action est facultative.', 'Configurer une action'],
    check: ['Regarde avant de tourner', 'Relis la scène entière. Vérifie les virages, les pieds au sol et le cadrage : ces détails se contrôlent en jeu.', 'Lire la scène'],
    film: ['Tout est prêt pour ta prise ?', 'Lance OBS, puis la prise propre. La vidéo suit ta plage de lecture, sans les panneaux de Director.', 'Lancer la prise propre']
  };
  function setText(el, text) { text=window.VantaI18n?.t(text)??text; if (el && el.textContent !== text) el.textContent = text; }
  function renderChecks(result) {
    const rows = [
      ['Caméra', result.hasCamera ? 'Plan configuré' : 'Aucun plan configuré', result.hasCamera],
      ['Sujets', result.missing ? result.missing + ' modèle(s) indisponible(s)' : result.actors ? result.actors + ' sujet(s) dans la scène' : 'Paysage sans sujet · possible', !result.missing],
      ['Lecture', Number.isFinite(result.first) && Number.isFinite(result.last) ? result.first.toFixed(1) + ' → ' + result.last.toFixed(1) + ' s' : 'Plage invalide', !result.problems.some(p => p.range)],
      ['Sauvegarde', savePending ? 'Enregistrement en cours' : saveDirty ? 'Modifications non enregistrées' : 'À jour', !saveDirty && !savePending],
      ['Aperçu', previewed ? 'Lecture lancée · vérifie le rendu en jeu' : 'À relire en jeu', previewed]
    ];
    const signature = JSON.stringify([rows, result.problems, result.warnings, step]);
    if (review.dataset.signature === signature) return; review.dataset.signature = signature;
    q('workflowChecks').replaceChildren(); q('workflowIssues').replaceChildren();
    for (const [name, text, okay] of rows) {
      const row = document.createElement('div'); row.className = 'workflow-check ' + (okay ? 'okay' : 'attention');
      const dot = document.createElement('span'); dot.textContent = okay ? '✓' : '·'; dot.setAttribute('aria-hidden', 'true');
      const body = document.createElement('div'), title = document.createElement('strong'), detail = document.createElement('small');
      title.textContent = name; detail.textContent = text; body.append(title, detail); row.append(dot, body); q('workflowChecks').append(row);
    }
    for (const item of [...result.problems.map(p => ({ ...p, blocking: true })), ...result.warnings]) {
      const box = document.createElement('div'); box.className = 'workflow-issue ' + (item.blocking ? 'blocking' : 'warning');
      const text = document.createElement('p'); text.textContent = item.text; box.append(text);
      if (item.step || item.save || item.preview) {
        const button = document.createElement('button'); button.type = 'button'; button.textContent = item.save ? 'Enregistrer' : item.preview ? 'Lire la scène' : 'Corriger';
        button.disabled = Boolean(item.save && (savePending || sessionRole === 'viewer'));
        button.onclick = () => {
          if (item.save) q('saveButton').click();
          else if (item.preview) q('previewButton').click();
          else { choose(item.step); if (item.range) { q('locationPanel').open = true; q('playbackFirst').focus(); } }
        }; box.append(button);
      }
      q('workflowIssues').append(box);
    }
  }
  function render() {
    const result = state(), actor = project.actors.find(a => a.id === selectedActorId), busy = root.classList.contains('editing-route');
    root.classList.toggle('guided', guided); root.dataset.workflowStep = step;
    root.classList.toggle('workflow-review', guided && ['check', 'film'].includes(step));
    setText(mode, guided ? 'Mode libre' : 'Mode guidé'); mode.setAttribute('aria-pressed', String(guided));
    const progress = [result.hasCamera, result.actors > 0 && !result.missing, result.movement, previewed, false];
    for (const [i, button] of [...nav.querySelectorAll('[data-step]')].entries()) {
      button.classList.toggle('active', guided && button.dataset.step === step); button.setAttribute('aria-current', guided && button.dataset.step === step ? 'step' : 'false');
      button.disabled = busy; button.title = busy ? 'Valide ou annule le trajet en cours.' : steps[i][1];
      setText(button.querySelector('.workflow-number'), progress[i] ? '✓' : String(i + 1));
    }
    const [title, hint, label] = copy[step];
    setText(q('workflowEyebrow'), 'ÉTAPE ' + (steps.findIndex(s => s[0] === step) + 1) + ' / 5'); setText(q('workflowTitle'), title); setText(q('workflowHint'), hint);
    const primary = q('workflowPrimary'); let reason = '';
    if (sessionRole === 'viewer' && step !== 'check') reason = 'Seul l’hôte peut modifier cette scène.';
    else if (busy) reason = 'Valide ou annule le trajet dans la vue.';
    else if (step === 'route' && !actor) reason = 'Choisis d’abord un sujet dans la liste de gauche.';
    else if (step === 'route' && actor.modelAvailable === false) reason = 'Ce modèle est indisponible. Recharge le projet ou retire ce sujet.';
    
    else if (step === 'film' && !result.ready) reason = result.problems[0].text;
    else if (step === 'check' && !result.hasCamera) reason = 'Ajoute d’abord une position de caméra.';
    else if (previewPlaying && ['camera', 'subject', 'route'].includes(step)) reason = 'Arrête la lecture pour modifier la scène.';
    primary.disabled = Boolean(reason || launching); primary.title = reason || label;
    setText(primary, launching ? 'Lancement…' : step === 'check' && previewPlaying ? 'Arrêter la lecture' : label);
    setText(q('workflowReason'), reason); q('workflowReason').hidden = !reason;
    q('workflowAtmosphere').hidden = !['camera', 'subject'].includes(step); q('workflowAtmosphere').disabled = busy;
    setText(q('workflowAtmosphere'), lookTabActive ? 'Revenir au cadrage / sujet' : 'Météo et lumière');
    const index = steps.findIndex(s => s[0] === step); q('workflowNext').hidden = step === 'film'; q('workflowNext').disabled = busy;
    setText(q('workflowNext'), 'Suivant : ' + (steps[index + 1]?.[1] || 'Filmer') + ' →');
    q('workflowRecording').hidden = step !== 'film';
    renderChecks(result);
    // Progressive disclosure, applied once to each newly rendered inspector section.
    for (const section of q('actorInspector').querySelectorAll(':scope > details')) {
      if (section.dataset.workflowReady) continue; section.dataset.workflowReady = 'true';
      const summary = section.querySelector('summary'), original = section.dataset.sectionKey || summary?.textContent || ''; 
      const translations = { Position: 'Position', Movement: 'Déplacement', Appearance: 'Apparence', Accessories: 'Accessoires', Attachment: 'Attache', 'Recorded take': 'Prise enregistrée' };
      if (summary && translations[original]) summary.textContent = translations[original];
      if (guided) section.open = original === 'Position' || (step === 'route' && original === 'Movement') || original.startsWith('Scheduled actions') || original === 'Recorded take';
    }
    if (guided && step === 'route') { const movement = [...q('actorInspector').querySelectorAll(':scope > details')].find(d => d.dataset.sectionKey === 'Movement'); if (movement) movement.open = true; }
    setText(q('saveButton'), savePending ? 'Enregistrement…' : 'Enregistrer');
    setText(q('saveState'), savePending ? 'Enregistrement…' : saveDirty ? 'Modifications non enregistrées' : 'Enregistré sur le serveur');
    for (const [id, text] of [['projectLibraryButton', 'Projets'], ['captureButton', guided ? 'Filmer' : 'Prise propre'], ['controlsButton', 'Raccourcis'], ['browseModelsButton', 'Choisir un modèle'], ['newCameraSequence', 'Ajouter un plan'], ['addKeyframeButton', 'Ajouter cette position']]) {
      const b = q(id); if (b?.querySelector('span')) setText(b.querySelector('span'), text); else if (b) setText(b, text);
    }
    if (guided && step === 'route') for (const button of q('actorInspector').querySelectorAll('.route-open,.route-edit-action')) setText(button, button.classList.contains('route-open') ? 'Dessiner un trajet' : 'Modifier le trajet');
    if (guided) {
      setText(q('cameraPane').querySelector('h1'), 'Plans et positions');
      setText(q('actorsPane').querySelector('h2'), 'Sujets de la scène');
      setText(q('cameraPane').querySelector('.panel-heading .eyebrow'), 'CADRAGE');
      setText(q('actorsPane').querySelector('.panel-heading .eyebrow'), 'MISE EN SCÈNE');
      setText(q('cameraPane').querySelector('.panel-intro'), 'Place la caméra, puis ajoute sa position au temps choisi.');
      setText(q('frameCount'), String(project.cameraShots?.length || project.keyframes.length).padStart(2, '0'));
      const details = q('cameraPane').querySelector('.keyframe-browser');
      const key = (project.id || '') + ':' + (project.selectedShotId || 0) + ':' + project.keyframes.length;
      if (details.dataset.workflowContext !== key) { details.dataset.workflowContext = key; details.open = project.keyframes.length > 0; }
      for (const [target, text] of [[details, 'Positions enregistrées'], [q('locationPanel'), 'Plage de lecture et cadrage'], [q('shotLibrary'), 'Plans automatiques'], [q('collaborationPanel'), 'Tournage à plusieurs']]) {
        const summary = target.querySelector('summary'); if (summary?.firstChild?.nodeType === Node.TEXT_NODE) setText(summary.firstChild, text + ' ');
      }
    }
  }
  // Keep steps synchronized with selections made directly in the existing editor.
  for (const [id, target] of [['cameraTab', 'camera'], ['inspectorCameraTab', 'camera'], ['actorsTab', 'subject'], ['viewSubject', 'subject']]) q(id)?.addEventListener('click', () => { if (!switching) { step = target; schedule(); } });
  window.addEventListener('message', event => {
    const data = event.data || {};
    if ((data.action === 'saveState' && !data.saved) || ['routeControls', 'close'].includes(data.action)) previewed = false;
    if (data.action === 'previewStarted' || (data.action === 'playhead' && data.playing)) { if (!previewed) { previewed = true; schedule(); } }
    if (data.action === 'library' && data.activeId !== review.dataset.projectId) { previewed = false; review.dataset.projectId = data.activeId; }
    if (['project', 'actors', 'saveState', 'saveResult', 'sessionState', 'open', 'captureEnd', 'routeControls', 'routeClosed', 'close'].includes(data.action)) schedule();
    if (data.action === 'playhead' && Boolean(data.playing) !== (q('workflowPrimary').dataset.playing === 'true')) { q('workflowPrimary').dataset.playing = String(Boolean(data.playing)); schedule(); }
  });
  window.VantaWorkflow = { render: schedule, invalidate() { previewed = false; schedule(); }, select: choose, guide(id) { guided = true; root.classList.add('guided'); choose(id); }, tab(scene) {
    if (!switching && scene !== 'look') step = scene ? (step === 'route' ? 'route' : 'subject') : 'camera';
    schedule();
  } };
  root.classList.add('guided');
  for (const id of ['shotLibrary', 'locationPanel', 'collaborationPanel', 'stagingTools', 'motionRecordPanel', 'actorCreate', 'automaticCamera']) q(id).open = false;
  render();
})();
