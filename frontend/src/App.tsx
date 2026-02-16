import './App.css';
import { LeftPanel } from './components/LeftPanel';

const App = () => {
  return (
    <div className="app-container">
      <header className="app-header">
        <h1>Research AI Assistant</h1>
      </header>
      <main className="app-main">
        <LeftPanel />
        <div className="middle-panel">
          {/* TODO: Answer/Response panel */}
          <div className="placeholder-panel">
            <p>Middle column - Answer panel</p>
          </div>
        </div>
        <div className="right-panel">
          {/* TODO: Connections panel */}
          <div className="placeholder-panel">
            <p>Right column - Connections panel</p>
          </div>
        </div>
      </main>
    </div>
  );
};

export default App;
