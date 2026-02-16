import { useState } from 'react';
import EntitySearchBar from './EntitySearchBar';
import type { EntitySuggestion } from '../../types';
import './LeftPanel.css';

const LeftPanel = () => {
  const [selectedEntity, setSelectedEntity] = useState<EntitySuggestion | null>(null);
  const [customPrompt, setCustomPrompt] = useState('');

  const handleEntitySelect = (entity: EntitySuggestion) => {
    setSelectedEntity(entity);
    // TODO: Load preset prompts based on entity type
    // TODO: Trigger connection retrieval for right column
  };

  const handleEntityClear = () => {
    setSelectedEntity(null);
  };

  return (
    <aside className="left-panel">
      <EntitySearchBar 
        onSelect={handleEntitySelect}
        onClear={handleEntityClear}
        selectedEntity={selectedEntity}
      />
      
      {selectedEntity && (
        <div className="prompt-buttons">
          <button className="prompt-btn">
            <span className="prompt-icon">📄</span>
            Executive Summary
          </button>
          <button className="prompt-btn">
            <span className="prompt-icon">💪</span>
            Strengths & Gaps
          </button>
        </div>
      )}

      <div className="custom-prompt-composer">
        <textarea
          className="prompt-textarea"
          placeholder="Write your question or instruction for the LLM…"
          value={customPrompt}
          onChange={(e) => setCustomPrompt(e.target.value)}
          rows={4}
        />
        <button className="ask-btn">
          Ask
        </button>
      </div>
    </aside>
  );
};

export default LeftPanel;
